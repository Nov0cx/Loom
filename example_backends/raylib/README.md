# ui_raylib

raylib for text rasterisation and input, `rlgl` immediate-mode triangles for everything Loom draws. The shortest of the backends, and the one to read if you want to see how little a backend has to do.

**A backend is only a backend.** The host calls `rl.InitWindow` and owns the loop; this backend never touches the window.

## Using it

```odin
rl.InitWindow(1280, 800, "app")

b: ui_raylib.Backend
backend := ui_raylib.init(&b)
defer ui_raylib.destroy(&b)

font := ui_raylib.load_face(&b, ttf_bytes)

ctx: ui.Context
ui.init(&ctx, {backend = backend, root = {font = font, font_size = 14}})

for !rl.WindowShouldClose() {
    input := ui_raylib.poll_input(&b)
    list  := demo.frame(&app, input)
    rl.BeginDrawing()
    rl.ClearBackground(...)
    ui_raylib.render(&b, list)
    rl.EndDrawing()
}
```

`Options`: `arc_segments` (default 6), `dpi` to override `rl.GetWindowScaleDPI`.

## Supported

- All six draw commands, with the same five shapes as the OpenGL backend: per-corner rounded rects, gradients evaluated per vertex, borders as concentric rings, ring-approximated shadows, a nested clip stack over `BeginScissorMode`.
- Glyph atlases baked per integer pixel size through `LoadFontFromMemory`, cached in a map, filtered bilinear.
- Key repeat via `IsKeyPressedRepeat`, UTF-8 text entry via `GetCharPressed`, all eight cursors, clipboard both ways.
- `register_texture(b, rl.Texture2D)` for `Cmd_Image`.

## Faked or missing

- **No detached dock panels.** raylib is single-window, so `Backend.viewports` is nil, `ui.dock_can_detach()` is false, and every dockspace silently degrades to `.In_Window`. This is the capability half of Loom's "detach is a capability, never an assumption" rule, and this backend is the case that proves it.
- **No idle path.** raylib cannot block on events, so an idle app still redraws at the target frame rate. The OpenGL backend's `glfw.WaitEventsTimeout` has no equivalent here; `SetTargetFPS` is the closest thing. Loom's `animating()` is still correct, there is just nothing useful to do with it.
- **Shadow blur, rounded image corners and rounded clipping** are the same approximations the OpenGL backend documents.
- **Letter spacing convention.** `measure_run` uses `MeasureTextEx` and drawing uses `DrawTextEx` with the identical spacing value, so measured and drawn widths always agree — but raylib applies spacing between glyphs (`(n-1) * spacing`) rather than after every glyph the way the contract describes. Since both halves are raylib, the difference is invisible; it does mean a non-zero `letter_spacing` measures a hair narrower here than on the OpenGL backend.
- **Vertical metrics come from `stbtt`**, not raylib, because raylib rasterises without exposing ascent or descent.

## Things worth knowing before porting

- `GetCharPressed` drains a queue and must be polled exactly once per frame.
- `BeginScissorMode` does not nest; the stack lives on `Backend.clip` and the intersection is always applied.
- The scissor is in physical pixels while everything else is logical, so it is scaled by `dpi`.
- All state — the path scratch buffers included — lives on `Backend`, never in package globals. The sketch this backend grew from kept its path scratch in `g_a`/`g_b` globals, which would corrupt across a DLL boundary.
