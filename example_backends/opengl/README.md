# ui_opengl — the reference backend

GLFW window handling plus an OpenGL 3.3 core renderer. This is the backend the other five are ported from: the tessellation, the atlas, the batching, the clip stack and the input translation are all written here first.

**A backend is only a backend.** It does not create the application window — the host does, and hands the `glfw.WindowHandle` to `init`. The only windows this backend creates are the secondary ones a detached dock panel needs, which the application never asks for and cannot know about.

## Using it

```odin
b: ui_opengl.Backend
backend := ui_opengl.init(&b, win)     // win is yours, already current
defer ui_opengl.destroy(&b)

font := ui_opengl.load_face(&b, ttf_bytes)

ctx: ui.Context
ui.init(&ctx, {backend = backend, root = {font = font, font_size = 14}})

for !glfw.WindowShouldClose(win) {
    glfw.PollEvents()
    input := ui_opengl.poll_input(&b)
    list  := demo.frame(&app, input)
    // clear, then
    ui_opengl.render(&b, list)
    glfw.SwapBuffers(win)
    ui_opengl.render_viewports(&b, ui.end_frame_viewports())
    if !ui.animating() do glfw.WaitEventsTimeout(0.25)
}
```

`init` calls `gl.load_up_to(3, 3, ...)` itself, so the host does not have to.

`Options`: `arc_segments` (default 6) trades geometry for smoother corners, `atlas_size` (default 1024) is the glyph page size, `dpi` overrides the window's content scale when you want to force a scale.

## Supported

- All six draw commands.
- Per-corner rounded rects, linear and radial gradients with multiple stops, rounded borders as concentric rings, nested clipping.
- Glyph atlases baked per integer pixel size at `round(size * dpi)`, packed into RGBA8 pages with a shelf packer, drawn one quad per glyph and snapped to the physical pixel grid.
- Key repeat, UTF-8 text entry, all eight `ui.Cursor` values, clipboard both ways.
- `Viewport_Ops`: detached dock panels as real OS windows, created with the host window as the share context. `ui.dock_can_detach()` is true.

## Faked or missing

- **Shadow blur.** There is no blur primitive; outer shadows are concentric rings of decreasing alpha and inset shadows are the same rings drawn inward. Large soft shadows look banded. A shader or a blurred nine-slice would do better and this backend already has shaders, so that is the obvious upgrade.
- **Rounded image corners.** `Cmd_Image.radius` is ignored. Round the container and let it clip.
- **Rounded clipping.** `Cmd_Push_Clip.radius` is ignored; the scissor is rectangular.
- **Kerning.** Advances come from `stbtt` horizontal metrics with no kern pairs, because the library measures arbitrary substrings and kerning across a substring boundary would make measurement non-pure.
- **Anti-aliasing.** Arcs rely on the window's MSAA. Ask for `glfw.SAMPLES` when you create the window.

## Things worth knowing before porting

- **The backend claims the GLFW user pointer** of every window it is given (`glfw.SetWindowUserPointer`), because a `proc "c"` callback has no other way to find its state and the library forbids package globals.
- **VAOs are not shared between GL contexts** even when buffers, textures and programs are. Each window gets its own VAO, keyed by handle in `Backend.wins`.
- **The scissor is in framebuffer pixels and Y-flipped**; clip rects are logical and Y-down. `apply_scissor` is the conversion, and getting it wrong is the most common porting bug.
- **`Backend.user` is shared by every proc including `measure_run`.** One struct, no aliasing.
- Character and scroll events are queues, not states: they are accumulated in callbacks and drained exactly once per `poll_input`.
