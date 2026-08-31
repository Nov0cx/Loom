# ui_vulkan_1_3

GLFW surface handling plus a Vulkan 1.3 renderer: dynamic rendering instead of a render pass, synchronisation2 barriers, one graphics pipeline with dynamic viewport and scissor, a per-frame ring of host-visible vertex and index buffers, a descriptor set per texture, and push constants for the projection.

This is `example_backends/vulkan_1_2` written against 1.3. It exists to show the difference, so the two folders are kept diffable — same eight files, same procs, same order. Read that one first if you want the full porting story; this README covers only what is different here.

**A backend is only a backend.** It does not create the application window — the host does, and hands the `glfw.WindowHandle` to `init`. The only windows this backend creates are the secondary ones a detached dock panel needs.

## Using it

```odin
glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)   // no GL context, this is Vulkan
win := glfw.CreateWindow(1280, 800, "app", nil, nil)

b: ui_vulkan_1_3.Backend
backend, ok := ui_vulkan_1_3.init(&b, win)
if !ok {
    fmt.eprintfln("%s", b.err)
    ui_vulkan_1_3.destroy(&b)
    return
}
defer ui_vulkan_1_3.destroy(&b)

font := ui_vulkan_1_3.load_face(&b, ttf_bytes)

ctx: ui.Context
ui.init(&ctx, {backend = backend, root = {font = font, font_size = 14}})

for !glfw.WindowShouldClose(win) {
    glfw.PollEvents()
    input := ui_vulkan_1_3.poll_input(&b)
    list  := demo.frame(&app, input)
    ui_vulkan_1_3.set_clear_color(&b, ui.theme().bg)
    ui_vulkan_1_3.render(&b, list)
    ui_vulkan_1_3.render_viewports(&b, ui.end_frame_viewports())
    if !ui.animating() do glfw.WaitEventsTimeout(0.25)
}
```

`init` returns `(ui.Backend, bool)` with a reason in `Backend.err`. It fails, rather than panics, when no device reports Vulkan 1.3 with `dynamicRendering` and `synchronization2` — which is the common case on older drivers, and exactly why the 1.2 backend still exists.

`Options`: `arc_segments` (default 6), `atlas_size` (default 1024), `dpi` override, `msaa` (default 4, clamped to device support, 1 disables it), `no_vsync`.

## Supported

Everything the 1.2 backend supports, identically: all six draw commands, per-corner rounded rects, gradients, ring borders, nested scissor clipping, MSAA with resolve, shelf-packed RGBA8 glyph atlases, full input and clipboard, all eight cursors, and `Viewport_Ops` for detached dock panels with their own surface and swapchain.

## Faked or missing

Identical to the 1.2 backend: ring-approximated shadow blur, `Cmd_Image.radius` and `Cmd_Push_Clip.radius` ignored, no kerning, `Cmd_Custom` runs during geometry accumulation rather than command recording, and a queue stall on frames that bake new glyphs. Dynamic rendering changes none of this — every one of these limits is in the draw layer, not the presentation layer.

## What 1.3 buys, concretely

Three objects the 1.2 backend has to own and rebuild are simply absent here:

- **No `VkRenderPass`.** The pipeline chains `PipelineRenderingCreateInfo{colorAttachmentCount = 1, pColorAttachmentFormats = &b.format}` into its `pNext` and leaves `renderPass` zero. The pipeline is no longer coupled to a render pass object at all.
- **No `VkFramebuffer`.** `Target` has no `fbs`, and `rebuild_target` has one fewer array to destroy and recreate on every resize. `CmdBeginRendering` takes the image views directly.
- **No `SubpassDependency`.** The implicit layout transitions the render pass performed are now two explicit `CmdPipelineBarrier2` calls in `begin_pass` and `end_pass`: `UNDEFINED → COLOR_ATTACHMENT_OPTIMAL` before rendering, `COLOR_ATTACHMENT_OPTIMAL → PRESENT_SRC_KHR` after.

Plus `QueueSubmit2` with `SemaphoreSubmitInfo`/`CommandBufferSubmitInfo`, which carries a per-semaphore stage mask instead of the parallel `pWaitDstStageMask` array.

Enabling all of this is two feature bits, chained into `VkDeviceCreateInfo.pNext` and verified during device selection:

```odin
f13 := vk.PhysicalDeviceVulkan13Features {
    sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
    dynamicRendering = true,
    synchronization2 = true,
}
```

`has_features` queries them back through `GetPhysicalDeviceFeatures2` before accepting a device, because a driver can report `apiVersion` 1.3 and still not offer both.

## Versus 1.2, by the numbers

| File | Δ lines | What changes |
|---|---:|---|
| `pipeline.odin` | −56 | no `make_render_pass`; `PipelineRenderingCreateInfo` in the pipeline `pNext` |
| `swapchain.odin` | −35 | no `Target.fbs`, no `make_framebuffer` |
| `backend.odin` | −7 | no `pass` field to create or destroy |
| `device.odin` | +15 | the 1.3 feature chain and its capability check |
| `render.odin` | +87 | `CmdBeginRendering`/`CmdEndRendering` plus two `CmdPipelineBarrier2` transitions, and `QueueSubmit2` |
| | **+4** | net |

`font.odin`, `input.odin` and `viewport.odin` are identical to the 1.2 versions apart from the package line.

So this backend is four lines *longer* than the 1.2 one, which is worth stating plainly because the usual claim is the opposite. Dynamic rendering removes two object lifetimes — real complexity, and the ones most likely to be got wrong on a resize path — but it does not remove the synchronisation those objects were performing. It relocates it, from a render pass declared once at startup into barriers written at the point of use. You trade a thing you must remember to rebuild for a thing you must remember to write. The 1.3 version is easier to follow, because the layout transitions are visible in the same 40 lines as the draw calls that depend on them; it is not smaller.

The atlas upload barriers deliberately stay on the Vulkan 1.0 `CmdPipelineBarrier` in **both** folders. Converting them to sync2 here would add a fourth diff hunk in `pipeline.odin` for no pedagogical gain — the sync2 story is easier to read when it is confined to `begin_pass`/`end_pass`.

## Things worth knowing before porting

All of the 1.2 backend's porting notes apply unchanged — the Y-down NDC, the UNORM surface format, `R8G8B8A8_UNORM` for atlas images, the render-complete semaphore being per swapchain *image*, resetting the fence only after a successful acquire, the frame ring living on `Target`, clamping the scissor, the two-pass `render`, the separate atlas upload submit, and one descriptor set per texture written exactly once. Read `../vulkan_1_2/README.md` for the reasoning behind each.

One note specific to 1.3: with MSAA on, `begin_pass` transitions **both** the multisampled attachment and the swapchain image, and sets `resolveMode = {.AVERAGE}` with `resolveImageView` pointing at the swapchain view. With MSAA off, `imageView` is the swapchain view and `resolveMode` is empty. Both paths have to work, because a device may only support 1× sampling.

## Shaders

Identical to the 1.2 backend: one Slang file with two entry points, compiled to committed `.spv` and embedded with `#load(..., []u32)`. `build.odin` regenerates them when `slangc` is available.

```
slangc shaders/ui.slang -target spirv -profile spirv_1_3 -entry vs_main -stage vertex   -o shaders/ui.vert.spv
slangc shaders/ui.slang -target spirv -profile spirv_1_3 -entry fs_main -stage fragment -o shaders/ui.frag.spv
```
