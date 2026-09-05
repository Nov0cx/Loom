# Loom

Loom is a UI library for Odin with an immediate-mode call style over a retained node tree, CSS-ish
styling (`:hover`, variants, transitions), multi-pass flexbox, and a dockspace whose panels can
optionally detach from the host window. It carries what a text editor needs: a full keyboard with an
ordered event stream, per-span coloured text with tab stops, a painter for shapes the props cannot
describe, and a virtual list.

It links no font stack and no renderer. The host supplies text measurement and consumes a flat draw
list, so the same UI code runs on raylib, OpenGL, D3D11, Vulkan or sokol without the library knowing
which.

## Building

Everything goes through `build.odin`:

```
odin run build.odin -file -- -help                          # the flag reference
odin run build.odin -file -- -target:lib                    # type-check the library on its own
odin run build.odin -file -- -target:tests                  # the headless suite
odin run build.odin -file -- -target:hot -run               # the headless host + plugin harness
odin run build.odin -file -- -target:hot_demo -run          # the windowed hot-reload demo
odin run build.odin -file -- -target:hot_panels             # rebuild just the panel DLL
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

## Keys

`Input.keys_down` and `Input.keys_pressed` answer "is it down", and `Input.key_events` is the ordered
stream that carries repeats, releases and the modifiers of each event. A host may fill either form;
`begin_frame` folds the stream into the sets, so filling only `key_events` still answers `key_pressed`
and `key_held`.

The stream is not routed, because a node does not exist yet when the frame opens. Instead it is read
in call order and taken from:

```odin
ui.begin_frame(input)
for &ev in ui.keys() {          // the global hook: read it before the tree
	if ev.key == .P && ev.mods == {.Ctrl} {
		open_palette()
		ev.consumed = true
	}
}
...
if ui.focus_within(pane) {      // a widget takes what is left, if it has the focus
	if ui.take_key(.S, {.Ctrl}) { save() }
}
```

## Text

A node's `text` takes `spans`, a sorted list of byte ranges with a colour, so a syntax-coloured line
is one node rather than one node per token. `Props.tab_size` puts tabs on a grid anchored at the
line's left edge, and `Props.tab_origin` is the pen x a piece of a line starts at, so a caller that
measures a line in pieces keeps every piece on one grid.

`caret_x(text, at, props)` and `offset_at(text, x, props)` map between a byte and a pixel. A backend
that fills the optional `offset_x` and `index_at` answers them from its own shaped-run cache, which
is both cheaper and correct across a ligature; without them Loom measures prefixes.

## Painting

`paint_rect`, `paint_line` and `paint_poly` put a shape in the current node's own slot of the draw
list, in coordinates local to the node, under the text or over it. A caret, a selection band, a
squiggle and a chevron are shapes, not props. `custom` is still there for a node that draws itself
with the host's renderer.

## Long lists

`virtual(count, row_h)` sizes a node for the whole list and reports the window of rows the viewport
shows, so only those are built. Rows must be one height; a soft-wrapped line is more rows, not a
taller one.

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

`tests/` holds the headless version of that contract. `demo_hotreload/` is the windowed one: the same
demo with its panels in a DLL that reloads while the window stays open, with the tree, scroll
positions and text carets intact. See `demo_hotreload/README.md` for what survives a reload and what
does not.

## License

See `LICENSE`.
