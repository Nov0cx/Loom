# ui_sokol

`sokol_app` for the window and input, `sokol_gfx` for rendering. The shortest backend after raylib, and the only one that is neither a raw API nor a framework with its own renderer — which is its whole value: it keeps the draw list honest about not assuming a GL-shaped world.

The bindings are vendored at a pinned commit under `third_party/sokol`; see the README there for why, and for how to rebuild the libraries on another platform. `-backend:sokol` passes `-define:SOKOL_DEBUG=false`, which is required for the committed release libraries to be found.

## The one backend where the host loop is inverted

`sokol_app` owns the loop. It calls you; you do not call it.

The resolution is that **this backend never calls `sapp.run` and never registers a callback.** The host owns all four callbacks and feeds two entry points:

- `handle_event(b, e)` from the host's `event_userdata_cb`, accumulating into the backend the same way the OpenGL backend's five GLFW callbacks accumulate into a `Win_State`.
- `poll_input(b)` at the top of the host's `frame_userdata_cb`, with the same drain-exactly-once contract as every other backend.

So the `ui.Backend` contract is unchanged. What changes is the shape of the *host's* loop, and that is a property of the demo, not of Loom.

## Using it

```odin
State :: struct { b: skb.Backend, ctx: ui.Context, app: demo.App, font: ui.Font, ok: bool }

main :: proc() {
    s: State
    sapp.run({
        user_data           = &s,
        init_userdata_cb    = init_cb,
        frame_userdata_cb   = frame_cb,
        event_userdata_cb   = event_cb,
        cleanup_userdata_cb = cleanup_cb,
        width = 1280, height = 800, sample_count = 4, high_dpi = true,
        window_title = "app",
        enable_clipboard = true, clipboard_size = 8192,
        logger = {func = slog.func},
    })
}

init_cb :: proc "c" (u: rawptr) {
    context = runtime.default_context()
    s := (^State)(u)
    sg.setup({environment = sglue.environment(), logger = {func = slog.func}})
    backend, ok := skb.init(&s.b)
    s.ok = ok
    s.font = skb.load_face(&s.b, ttf_bytes)
    ui.init(&s.ctx, {backend = backend, root = {font = s.font, font_size = 14}})
    demo.init_app(&s.app)
}

frame_cb :: proc "c" (u: rawptr) {
    context = runtime.default_context()
    s := (^State)(u)
    input := skb.poll_input(&s.b)
    list  := demo.frame(&s.app, input)
    skb.set_clear_color(&s.b, ui.theme().bg)
    skb.render(&s.b, list)
}

event_cb :: proc "c" (e: ^sapp.Event, u: rawptr) {
    context = runtime.default_context()
    skb.handle_event(&(^State)(u).b, e)
}
```

Four things about that shape are worth stating, because they are what make the sokol host different from the other five:

- **`init` must run inside `init_cb`, never in `main`.** Every `sg.*` call is illegal before `sg.setup`, and `sg.setup` needs `sglue.environment()`, which needs a live `sokol_app` window.
- **The state aggregate is a local in `main`.** `sapp.run` blocks until the window closes, so that stack frame outlives every callback, and `sapp.Desc.user_data` carries the pointer. No package globals — the same rule the other backends satisfy through the window user pointer.
- **`cleanup_cb` does what the other hosts express as `defer`,** in this order: `settings_save_file`, `destroy_app`, `ui.destroy`, `skb.destroy`, `sg.shutdown`.
- **Every callback is `proc "c"` and must open with `context = runtime.default_context()`.**

`Options`: `arc_segments` (default 6), `atlas_size` (default **512**, not 1024 — see below), `dpi` to override `sapp.dpi_scale`.

## Supported

- All six draw commands, with the same five shapes as the OpenGL backend: per-corner rounded rects, gradients evaluated per vertex, borders as concentric rings, ring-approximated shadows, a nested clip stack over `sg.apply_scissor_rect`.
- Glyph atlases baked with `stbtt` per integer pixel size into RGBA8 shelf-packed pages.
- Key repeat from `Event.key_repeat`, UTF-8 text entry from `.CHAR` events, all eight cursors, clipboard both ways.
- `register_texture(b, img, w, h)` to adopt an existing `sg.Image`, or `load_texture(b, w, h, rgba)` to make one.
- One shader written three times — GLSL 4.1, HLSL SM4 and MSL — selected on `sg.query_backend()`, so no `sokol-shdc` step is needed anywhere in the build.

## Faked or missing

- **No detached dock panels.** `sokol_app` is single-window, so `Backend.viewports` is nil, `ui.dock_can_detach()` is false, and every dockspace degrades to `.In_Window` — the same capability story as raylib, and the reason two of the six backends are single-window on purpose.
- **No idle path.** `sokol_app` cannot block on events, so an idle app redraws at the swap interval. `ui.animating()` is still correct; there is simply nothing to do with it. Identical to raylib's documented limitation.
- **`Input.window_pos` is always `{0, 0}`.** sokol has no window-position query. Harmless, because `window_pos` only exists to place detached viewports and there are none.
- **The mouse position is only known from events.** sokol delivers `mouse_x`/`mouse_y` inside events and offers no query, so it is cached on move/down/up/scroll/enter. On a frame where the mouse did not move, the cached value is one frame stale — invisible in an immediate-mode UI.
- **Vertex and index buffers are fixed-size and grow one frame late.** sokol buffers cannot be resized and destroying a bound buffer mid-frame is invalid, so a frame that overflows the current capacity is clipped to what fits and the buffer is enlarged before the next one. Starting capacity is 64K vertices / 128K indices, which the demo never comes close to. This is the honest cost of sokol's resource model rather than something to work around.
- **Shadow blur, rounded image corners and rounded clipping** are the same approximations the OpenGL backend documents.
- **`Cmd_Custom` cannot issue its own draws through this backend.** As with the Vulkan and D3D11 backends, geometry is accumulated for the whole frame and replayed afterwards. The pipeline and uniforms are re-applied after every custom batch so a custom draw cannot leak state into what follows.
- **`.VULKAN` and `.WGPU` are refused.** Both need SPIR-V or WGSL bytecode, which is exactly what avoiding `sokol-shdc` costs. `init` returns false with a reason in `b.err`. On desktop sokol picks D3D11 on Windows, GLCORE on Linux and Metal on macOS, so this never fires in practice.

## Things worth knowing before porting

- **sokol normalises NDC to the GL convention on every backend, and image origin to top-left.** So all three shader sources keep the same `1.0 - y / size.y * 2.0` flip as the OpenGL and D3D11 backends, and `sg.apply_scissor_rect(..., origin_top_left = true)` needs no Y inversion. One shader shape, three languages — the strongest single argument for sokol as the portable example.
- **Writing `sg.Shader_Desc` by hand instead of running `sokol-shdc` is entirely reasonable for a shader this small,** and it keeps the shader next to the code that uses it, the way the OpenGL backend's GLSL is. The reflection data shdc would generate is the `attrs`, `uniform_blocks`, `views`, `samplers` and `texture_sampler_pairs` arrays in `shader.odin`.
- **The uniform block must be 16 bytes, not 8.** Both std140 and the D3D constant-buffer rule round up, and sokol asserts on the mismatch. Hence `float4 u_size` with only `.xy` used — the standard no-shdc workaround.
- **On the GL backend the uniform must be a plain global `uniform`, not a UBO,** because sokol's GL path sets it by name with `glUniform4fv`. And use `#version 410`, not 330: `SOKOL_GLCORE` targets 4.1 because that is macOS's ceiling.
- **`sg.update_buffer` is once per frame per buffer.** That single fact rules out the OpenGL backend's flush-and-draw-immediately architecture and forces the Vulkan-style accumulate-then-replay shape. It is not a preference.
- **`sg.update_image` replaces the whole image,** is allowed at most once per frame per image, and is illegal between `begin_pass` and `end_pass`. So the atlas keeps its CPU pixels, sets a per-page dirty *flag* (no rect — the whole page goes anyway), and `flush_atlas` runs from `render` before the pass. Fresh pages start dirty so they are never sampled before their first upload, and atlas pages are `dynamic_update` with no initial data, which sokol requires.
- **`DEFAULT_ATLAS_SIZE` is 512 here, not 1024, and that is deliberate.** A dirty page costs `atlas_size² * 4` bytes per upload — 4 MB at 1024, 1 MB at 512. The dirty flag coalesces, so a first frame that packs three hundred glyphs pays once rather than three hundred times, and in steady state new glyphs are rare. But typing a character never seen before costs one whole-page upload that frame, and 1 MB is a much better number than 4. The trade is more pages and therefore more batch breaks in `draw_text`, which is far cheaper.
  If that ever genuinely matters, `sg.Image_Desc` accepts a natively created `d3d11_texture` / `gl_textures` / `mtl_textures`, which you could then update with the native API. That is the door out; taking it defeats the point of having a sokol backend at all.
- **`sapp.width()` and `sapp.height()` are framebuffer pixels, not logical ones,** so divide by `sapp.dpi_scale()` for `Input.viewport` — and the same for the mouse. Getting this backwards renders everything at half size on a hi-DPI display.
- **The clipboard needs host opt-in:** `enable_clipboard = true` and a non-zero `clipboard_size` in `sapp.Desc`. Without them `get_clipboard_string` returns empty and Ctrl+V silently does nothing.
- `.CHAR` events carry a full codepoint in `char_code`, so there is no surrogate reassembly to do — a pleasant contrast with the D3D11 backend's `WM_CHAR`.
- All state lives on `Backend`, never in package globals. There is no `wins` map and no `Vp`: one window means `Win_State` is a plain field, which is about thirty lines less than the GLFW backends.
