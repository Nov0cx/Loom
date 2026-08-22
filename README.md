# Loom

Loom is a UI library for Odin with an immediate-mode call style over a retained node tree, CSS-ish
styling (`:hover`, variants, transitions), multi-pass flexbox, and a dockspace whose panels can
optionally detach from the host window.

It links no font stack and no renderer. The host supplies text measurement and consumes a flat draw
list, so the same UI code runs on raylib, OpenGL, D3D11, Vulkan or sokol without the library knowing
which.

## Building

Everything goes through `build.odin`:

```
odin run build.odin -file -- -help                          # the flag reference
odin run build.odin -file -- -target:lib                    # type-check the library on its own
odin run build.odin -file -- -target:tests                  # the headless suite
odin run build.odin -file -- -target:hot -run               # the host + plugin hot-reload harness
odin run build.odin -file -- -target:demo -backend:raylib -run
odin run build.odin -file -- -target:demo -backend:vulkan_1_3 -mode:release -run
odin run build.odin -file -- -target:all
odin run build.odin -file -- -clean
```

## The frame pipeline

```
host polls platform            -> ui.Input
ui.begin_frame(input)             reset per-frame arena, ingest input,
                                  recompute State_Set from LAST frame's rects
user code                         begin/leaf/scope/end calls build (or re-touch)
                                  the retained tree; each call returns an
                                  Interaction describing LAST frame's rect
ui.end_frame()
  1. prune                        nodes untouched for Config.prune_after frames
  2. cascade                      base -> group_hover -> hover -> focus ->
                                  active -> disabled -> rules, then inherit
  3. animate                      step transitions toward the cascaded target
  4. layout                       multi-pass flex over `computed`
  5. emit                         walk in paint order -> Draw_List
host renders Draw_List
```

Downside is a one frame lag.

## Hot reload

An executable and a DLL can both draw into the same context. The DLL adopts the host's state in its
load entry point, before any UI call:

```odin
@(export)
plugin_load :: proc "c" (l: ^link.Link) {
	context = l.odin_ctx
	ui.set_globals(l.ui_globals)
	ui.make_current(l.ui_ctx)
}
```

A reload zeroes the DLL's own globals, so `plugin_load` must re-adopt every time — that is why this
is two explicit procs rather than lazy initialisation. `set_globals` asserts that `VERSION`,
`size_of(Context)` and `size_of(Node)` match, which turns a stale-DLL mismatch into an assert on load
instead of a crash later.

## License

See `LICENSE`.
