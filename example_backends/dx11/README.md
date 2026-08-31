# ui_dx11

Raw Win32 for the window and input, Direct3D 11 for rendering. The only backend with no windowing library underneath it, which is the point: everything GLFW hides in the OpenGL and Vulkan backends is spelled out here.

**A backend is only a backend.** The host calls `create_window` (or makes its own `HWND` any way it likes) and owns the message pump; this backend adopts the window and answers questions about it.

Seven source files rather than the usual six. The extra one is `window.odin`, which does what `vendor:glfw` does for three of the other backends.

## Using it

```odin
ui_dx11.enable_dpi_awareness()

b: ui_dx11.Backend
hwnd := ui_dx11.create_window(&b, "app", 1280, 800)

backend, ok := ui_dx11.init(&b, hwnd)
if !ok { fmt.eprintln(b.err); return }
defer ui_dx11.destroy(&b)
win.ShowWindow(hwnd, win.SW_SHOW)

font := ui_dx11.load_face(&b, ttf_bytes)

ctx: ui.Context
ui.init(&ctx, {backend = backend, root = {font = font, font_size = 14}})

for !quit {
    msg: win.MSG
    for win.PeekMessageW(&msg, nil, 0, 0, win.PM_REMOVE) {
        if msg.message == win.WM_QUIT { quit = true }
        win.TranslateMessage(&msg)
        win.DispatchMessageW(&msg)
    }
    if ui_dx11.should_close(&b) { quit = true }

    input := ui_dx11.poll_input(&b)
    list  := demo.frame(&app, input)

    ui_dx11.set_clear_color(&b, ui.theme().bg)
    ui_dx11.render(&b, list)
    ui_dx11.render_viewports(&b, ui.end_frame_viewports())

    if !ui.animating() {
        win.MsgWaitForMultipleObjects(0, nil, false, 1000, win.QS_ALLINPUT)
    }
}
```

`init` returns `(ui.Backend, bool)` rather than asserting, because device creation genuinely fails on machines without D3D11 hardware. The reason is in `b.err`.

`Options`: `arc_segments` (default 6), `atlas_size` (default 1024), `dpi` to override `GetDpiForWindow`, `msaa` (default 4, clamped down to what the adapter supports), `no_vsync`.

`TranslateMessage` is not optional — without it Windows never synthesises `WM_CHAR` and text input is silently dead.

`MsgWaitForMultipleObjects` rather than `GetMessage` is what makes the idle path work. It is the exact analogue of `glfw.WaitEventsTimeout`: it returns on a message *or* after the timeout, and it does not remove the message, so the next `PeekMessage` loop drains it normally. `GetMessage` blocks forever and cannot express "wake on input, or in one second to keep animating".

## Supported

- All six draw commands, with the same five shapes as the OpenGL backend: per-corner rounded rects, gradients evaluated per vertex, borders as concentric rings, ring-approximated shadows, a nested clip stack over `RSSetScissorRects`.
- Glyph atlases baked with `stbtt` per integer pixel size into RGBA8 shelf-packed pages, uploaded as coalesced dirty sub-rects with `UpdateSubresource`.
- Full `Viewport_Ops`: detached dock panels become real top-level windows with their own swap chain.
- Key repeat from the `WM_KEYDOWN` repeat bit, UTF-8 text entry from `WM_CHAR` (surrogate pairs reassembled), all eight cursors, clipboard both ways through `CF_UNICODETEXT`.
- `register_texture(b, srv, w, h)` to adopt an existing `ID3D11ShaderResourceView`, or `load_texture(b, w, h, rgba)` to make one.

## Faked or missing

- **No live resize.** Win32's modal move/size loop blocks `PeekMessage`, so the window freezes while you drag its edge and repaints when you let go. The honest fix is to call the host's frame function from inside the `WndProc` on a `WM_TIMER`, which would mean the backend owning the frame callback — precisely the inversion this backend exists to avoid. Documented rather than fixed, the same way the raylib backend documents its missing idle path.
- **Shadow blur, rounded image corners and rounded clipping** are the same approximations the OpenGL backend documents. This backend has shaders and could do better with an SDF; it doesn't, so that all six stay comparable.
- **`Cmd_Custom` cannot issue its own draws through this backend.** Like the Vulkan backends, geometry is accumulated for the whole frame and replayed afterwards, so a custom callback runs during replay. It may draw with the device directly; `apply_state` is re-run after every custom batch so it cannot leak pipeline state into the batches that follow.
- **The swap chain uses the DISCARD swap effect, not the flip model,** because MSAA back buffers are incompatible with `FLIP_DISCARD`/`FLIP_SEQUENTIAL` and the demo defaults to 4x like the others. The cost is no `ALLOW_TEARING` and slightly more latency. The upgrade is a flip-model chain plus a separate MSAA render target and a `ResolveSubresource` before `Present`; about sixty more lines and a second texture.
- **The shader is compiled at runtime with `D3DCompile`,** so it can live next to the code that uses it the way the OpenGL backend's GLSL does. A shipping app compiles with `fxc` at build time and `#load`s the bytecode.

## Things worth knowing before porting

- **D3D11 clip space is Y-up, exactly like OpenGL.** The vertex shader keeps the GL flip (`1.0 - pos.y / size.y * 2.0`) because Loom hands you top-left-origin logical pixels. The Vulkan backends omit that flip because *Vulkan* NDC points down — that difference is about Vulkan, not about D3D, and copying the wrong one is the fastest way to render everything upside down.
- **The scissor is top-left origin,** so unlike OpenGL there is no `fb.y - (y + h)` inversion — only a multiply by the DPI scale. It must still be clamped to the target: the debug layer errors on `right < left`, and the dockspace routinely emits clip rects that overhang the window. Two more traps: `ScissorEnable` must be true on the rasteriser state, and with it enabled the default scissor is `(0,0,0,0)`, so a rect has to be set before the *first* `DrawIndexed`, not only when the clip changes.
- **DPI works the opposite way round from GLFW.** GLFW hands you a logical window size and a physical framebuffer size and you divide. Win32 gives you physical pixels only, so you take `GetDpiForWindow` as the scale and *divide* to get logical. The mouse from `ScreenToClient` is physical too.
- **Geometry is accumulated then replayed, not flushed per batch.** OpenGL's `glBufferData(STREAM_DRAW)` per flush is idiomatic and drivers are tuned for it; the D3D11 equivalent, `Map(WRITE_DISCARD)`, renames the buffer every call, and a Loom frame flushes on the order of two hundred times. Two passes means one map per buffer per frame.
- **The atlas is a `DEFAULT` texture updated with `UpdateSubresource` and a `D3D11_BOX`,** not a `DYNAMIC` one. `WRITE_DISCARD` on a texture throws away the whole surface, so adding one glyph would re-upload four megabytes. With a box, `pSrcData` must point at the first pixel *of the box* and the pitch is the source stride.
- **The `WndProc` finds its state through `GWLP_USERDATA`,** which holds a `^Win_State` carrying both the backend pointer and the previous window proc. `adopt_window` subclasses rather than requiring its own class, so a host that made the `HWND` itself still gets input. A host must therefore not use `GWLP_USERDATA` on an adopted window; `handle_message` is public for hosts that would rather chain the proc themselves.
- **Modifiers are read with `GetKeyState` in `poll_input`, never tracked from messages.** Message-tracked modifiers desync the moment focus changes with a key held, and then Ctrl appears stuck down forever.
- **The mouse position is read with `GetCursorPos` + `ScreenToClient`, not from `lParam`.** It mirrors `glfw.GetCursorPos`, it still works on a frame where nothing moved, and it avoids `GET_X_LPARAM`'s sign-extension trap on a monitor placed left of or above the primary.
- **`SetCapture` on the first button down and `ReleaseCapture` when the last comes up.** Without it, dragging a slider or tearing out a dock tab stops the instant the cursor leaves the window.
- **The class must not set `CS_DBLCLKS`.** Loom does its own double-click timing through `Config.double_click`; with `CS_DBLCLKS` the second press arrives as `WM_LBUTTONDBLCLK`, Loom never sees a `WM_LBUTTONDOWN`, and `Interaction.double_clicked` quietly stops working.
- **`WM_SETCURSOR` is the only correct place to call `SetCursor`.** Windows resets the cursor on every mouse move, so setting it from `Backend.set_cursor` alone gets undone within a frame.
- **`WM_SIZE` records that a resize happened; it does not resize the swap chain.** That is done lazily at the top of `render`, and it releases the render target view *before* `ResizeBuffers` — not doing so returns `E_INVALIDARG` and is the most common D3D11 resize bug.
- **Never `DestroyWindow` from inside `WM_CLOSE`.** For the main window the host decides via `should_close`; for a viewport Loom decides via `Viewport_Events.closed`. Destroying it early leaves Loom holding a dead handle.
- The swap chain format is plain `R8G8B8A8_UNORM`, never `_SRGB`, matching the OpenGL and Vulkan backends. Loom's colours are authored non-linearly and an sRGB target double-encodes them.
- All state lives on `Backend`, never in package globals — the `WndProc` gets at it through the window user pointer for exactly that reason.
