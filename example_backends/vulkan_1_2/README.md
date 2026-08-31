# ui_vulkan_1_2

GLFW surface handling plus a Vulkan 1.2 renderer: one render pass, framebuffers per swapchain image, one graphics pipeline with dynamic viewport and scissor, a per-frame ring of host-visible vertex and index buffers, a descriptor set per texture, and push constants for the projection. It is the longest of the backends by a wide margin and is deliberately kept linear rather than abstracted.

**A backend is only a backend.** It does not create the application window — the host does, and hands the `glfw.WindowHandle` to `init`. The only windows this backend creates are the secondary ones a detached dock panel needs.

## Using it

```odin
glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)   // no GL context, this is Vulkan
win := glfw.CreateWindow(1280, 800, "app", nil, nil)

b: ui_vulkan_1_2.Backend
backend, ok := ui_vulkan_1_2.init(&b, win)
if !ok {
    fmt.eprintfln("%s", b.err)
    ui_vulkan_1_2.destroy(&b)
    return
}
defer ui_vulkan_1_2.destroy(&b)

font := ui_vulkan_1_2.load_face(&b, ttf_bytes)

ctx: ui.Context
ui.init(&ctx, {backend = backend, root = {font = font, font_size = 14}})

for !glfw.WindowShouldClose(win) {
    glfw.PollEvents()
    input := ui_vulkan_1_2.poll_input(&b)
    list  := demo.frame(&app, input)
    ui_vulkan_1_2.set_clear_color(&b, ui.theme().bg)
    ui_vulkan_1_2.render(&b, list)
    ui_vulkan_1_2.render_viewports(&b, ui.end_frame_viewports())
    if !ui.animating() do glfw.WaitEventsTimeout(0.25)
}
```

Two host-facing differences from the OpenGL backend, both forced by Vulkan:

- **`init` returns `(ui.Backend, bool)`** and leaves a reason in `Backend.err`. A perfectly valid machine can lack Vulkan 1.2, and panicking on that would be wrong. Call `destroy` on the failure path too; it is safe on a partly built backend.
- **The clear belongs to the backend.** The GL host does its own `gl.Clear`; there is no equivalent outside a render pass, so the clear is the render pass's `loadOp` and `set_clear_color` feeds it. The host no longer touches the framebuffer, and there is no `SwapBuffers` — `render` acquires, records, submits and presents.

`Options`: `arc_segments` (default 6) trades geometry for smoother corners, `atlas_size` (default 1024) is the glyph page size, `dpi` overrides the window's content scale, `msaa` (default 4, clamped to what the device supports, 1 disables it), `no_vsync` selects `MAILBOX`/`IMMEDIATE` over `FIFO`.

`no_vsync` is the one knob the other backends leave to the host. It has to live here because the swapchain does.

## Supported

- All six draw commands.
- Per-corner rounded rects, linear and radial gradients with multiple stops, rounded borders as concentric rings, nested clipping via `vkCmdSetScissor`.
- MSAA through a multisampled colour attachment that resolves into the swapchain image, so the tessellated arcs match the OpenGL backend's quality.
- Glyph atlases baked per integer pixel size at `round(size * dpi)`, packed into RGBA8 pages with a shelf packer, uploaded through a staging buffer as one dirty rect per page per frame.
- Key repeat, UTF-8 text entry, all eight `ui.Cursor` values, clipboard both ways.
- `Viewport_Ops`: detached dock panels as real OS windows, each with its own surface, swapchain, framebuffers and frame ring, sharing the instance, device, pipeline, sampler, descriptor sets and glyph atlas. `ui.dock_can_detach()` is true.
- Validation layers and a debug messenger under `ODIN_DEBUG`, enabled only when the layer is actually installed.

## Faked or missing

- **Shadow blur.** No blur primitive; outer shadows are concentric rings of decreasing alpha and inset shadows are the same rings drawn inward, exactly as in the OpenGL backend. Large soft shadows band. This backend has shaders and could do better with an SDF; it does not yet.
- **Rounded image corners.** `Cmd_Image.radius` is ignored. Round the container and let it clip.
- **Rounded clipping.** `Cmd_Push_Clip.radius` is ignored; the scissor is rectangular.
- **Kerning.** Advances come from `stbtt` horizontal metrics with no kern pairs, because the library measures arbitrary substrings.
- **`Cmd_Custom` is narrower here than on OpenGL.** `render` accumulates all geometry first and records commands second, so when the callback runs there is no open `VkCommandBuffer` for it to draw into. It is invoked in the right z-order and under the right clip, and it can append geometry through the backend, but it cannot issue its own draw calls the way a GL callback could.
- **A new glyph costs a queue stall.** Frames that bake glyphs submit the atlas upload on a dedicated command buffer and `vkQueueWaitIdle` before recording. That is cold-start cost, not per-frame cost — the atlas converges within a few frames and is cached per integer pixel size. See the note below on why it is not folded into the frame's command buffer.

## Things worth knowing before porting

- **Vulkan's NDC is Y-down.** The OpenGL vertex shader writes `1.0 - y / size.y * 2.0`; here it is `y / size.y * 2.0 - 1.0`. Copying the GL shader verbatim renders the entire UI upside down, and that is the first thing to check if it does.
- **Pick a UNORM surface format, never `_SRGB`.** Loom's colours are already authored non-linearly, so an sRGB swapchain encodes them a second time and the whole UI washes out. `pick_format` prefers `B8G8R8A8_UNORM`, then `R8G8B8A8_UNORM`.
- **The atlas and texture images are `R8G8B8A8_UNORM` regardless of the surface format.** They hold RGBA bytes; letting them inherit a `B8G8R8A8` swapchain format swaps red and blue in every glyph.
- **The render-complete semaphore is per swapchain *image*; the image-available semaphore is per frame in flight.** Making both per-frame is the classic Vulkan-UI bug: present can still be waiting on a semaphore for one image while a later frame re-signals it for another. The per-frame one is safe because its fence is waited first.
- **Reset the frame fence only after a successful acquire.** Resetting first and then bailing on `ERROR_OUT_OF_DATE_KHR` leaves the fence unsignalled and the next frame hangs in `WaitForFences`. It only shows up when you resize.
- **The frame ring lives on `Target`, not on `Backend`.** One host frame renders the main window and every detached panel; a shared ring would let a viewport overwrite the main window's still-in-flight vertex buffer. OpenGL hides this because `glBufferData` orphans implicitly.
- **The scissor is Y-down here, so the OpenGL Y-flip goes away** — but it must be clamped to the swapchain extent. A negative offset or an extent past the framebuffer is a validation error where GL silently ignored it, and the dockspace produces over-hanging clip rects routinely.
- **`render` is two passes: accumulate, then record.** `flush` no longer draws; it closes a `Batch` of `(first, count, descriptor set, clip)`. That restructure is what makes the atlas upload easy — every glyph the frame needs is baked before the command buffer opens — and it is why the whole tessellation layer is unchanged from the OpenGL backend.
- **The atlas upload is its own submit with a fence wait, not part of the frame's command buffer.** Folding it in is faster and wrong once viewports exist: the main window's `render` uploads pages and a detached window's `render` samples them in a *separate* submit, and submits to one queue are not ordered against each other. That would be a garbage glyph in the detached window roughly once a week.
- **Every texture gets its own descriptor set, written once at creation and never rewritten.** That makes the set a perfect batching key and makes it structurally impossible to update a set a submitted frame is still reading. Do not "optimise" this into one rebound set.
- **There is no per-context object problem.** The OpenGL backend keys a VAO per window because VAOs are not shared between contexts; Vulkan resources are device-scoped, so viewports share the pipeline, sampler, descriptor sets and atlas outright. `Backend.wins` here is only input state.
- **MSAA sample counts must be clamped** against `limits.framebufferColorSampleCounts`; a device may only support 1×, and both paths have to work.

## Shaders

One Slang file, `shaders/ui.slang`, with a vertex and a fragment entry point. The compiled `shaders/*.spv` are committed and embedded with `#load("shaders/ui.vert.spv", []u32)`, which yields a correctly typed and aligned `[]u32` — no reinterpret or alignment trick needed.

`build.odin` recompiles them before building the demo when `slangc` is on `PATH` or under `VULKAN_SDK`, and prints a skip note when it is not, so the Vulkan SDK is a contributor dependency rather than a build dependency. To do it by hand:

```
slangc shaders/ui.slang -target spirv -profile spirv_1_3 -entry vs_main -stage vertex   -o shaders/ui.vert.spv
slangc shaders/ui.slang -target spirv -profile spirv_1_3 -entry fs_main -stage fragment -o shaders/ui.frag.spv
```

Slang names both SPIR-V entry points `main`, so the pipeline uses `pName = "main"` for each stage.

## 1.2 versus 1.3

`example_backends/vulkan_1_3` is this backend written against Vulkan 1.3, kept structurally parallel so `diff -r` reads as the changelog. Same eight files, same procs, same order; `font.odin`, `input.odin` and `viewport.odin` differ only by the package line.

| File | Δ lines | What changes |
|---|---:|---|
| `pipeline.odin` | −56 | `make_render_pass` disappears; `PipelineRenderingCreateInfo` goes in the pipeline's `pNext` and `renderPass` is left zero |
| `swapchain.odin` | −35 | `Target.fbs` and `make_framebuffer` disappear; there is nothing to rebuild per image but the view |
| `backend.odin` | −7 | no `pass` field to create or destroy |
| `device.odin` | +15 | `PhysicalDeviceVulkan13Features{dynamicRendering, synchronization2}` chained into device creation, and checked during device selection |
| `render.odin` | +87 | `CmdBeginRenderPass`/`CmdEndRenderPass` become `CmdBeginRendering`/`CmdEndRendering` wrapped in two explicit `CmdPipelineBarrier2` transitions, and the submit becomes `QueueSubmit2` |
| | **+4** | net |

The honest summary is not "1.3 is shorter" — it is four lines longer. Dynamic rendering deletes two object lifetimes you otherwise have to rebuild on every resize (the render pass and a framebuffer per swapchain image), and in exchange it makes the layout transitions the render pass was performing implicitly into barriers you write yourself. The work does not vanish; it moves from a declarative object created once into explicit, visible synchronisation at the point of use. Whether that is an improvement depends on whether you would rather read the transitions or trust them.
