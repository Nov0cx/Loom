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

`begin_frame`/`end_frame` run that pipeline once, and anything that changes while user code runs
shows one frame late. `frame` runs it again when a pass changed something, against the rects that
pass just laid out, and emits only the last pass:

```odin
for ui.frame(input) {
	build_ui()
}
list := ui.draw_list()
```

A repeat runs when the frame had an input edge, a widget reported `changed`, a node was created,
`set_focus` or `request_pass` was called, or the node under the pointer moved. An idle frame runs
once. `Config.max_passes` caps it, 3 by default; 1 restores the single pass.

User code may therefore run up to three times per frame. Input edges (presses, releases, keys, typed
text, wheel) and `dt` arrive only in the first pass, so `if ui.button("Go").clicked {}` still fires
once. Work that does not depend on input, such as appending to a log every frame, runs once per pass.

Only a node that asks for the pointer is hit-tested: `.Clickable`, `.Focusable`, `.Draggable`, a
scrolling one, `.Wheel`, or `.Hoverable`. `.Hoverable` is the one that is no button — a label or a
chip that only wants to hover, to wear a hover style or to carry a `tooltip`. It takes the hit from
whatever is under it, so never put one over a node that must stay clicked.

`Element.hit_pad` grows the hit area on each side and leaves the drawn rect as it is, for a thin
splitter or a small icon. `Dock_Config.splitter_hit` gives the dock splitters a grab width larger
than the bar they draw.

## Motion

`Element.transition` animates the listed props of a node toward their new value. `Transition.snap`
names states that take their target at once and animate only on the way out: `snap = {.Hover,
.Active}` gives an instant hover in and a fade out. `.No_Anim` turns one node off;
`set_reduce_motion(true)` (or `Config.no_anim`) turns off every transition, the scroll-to tween,
scroll inertia and the caret blink of `input`.

A new node takes no transition on its first frame. `Element.enter` names the props it starts from
instead, and it then animates to its own: `enter = {opacity = 0}` with an opacity transition fades a
modal in.

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

Tab and Shift+Tab that nothing took move the focus over `.Focusable` nodes in tree order.
`Element.focus_scope` keeps that cycle inside a subtree: the nearest scope above the focus, or the
last scope declared when the focus is outside every scope. A modal sets it on its root.
A node with the focus also has the state `.Focus_Visible` when the focus came from Tab or Shift+Tab,
and not when a click moved it. A focus ring keyed on it (a `Rule` with `on = {.Focus_Visible}`)
shows for the keyboard only.

## Text

A node's `text` takes `spans`, a sorted list of byte ranges with a colour, so a syntax-coloured line
is one node rather than one node per token. `Props.tab_size` puts tabs on a grid anchored at the
line's left edge, and `Props.tab_origin` is the pen x a piece of a line starts at, so a caller that
measures a line in pieces keeps every piece on one grid.

`caret_x(text, at, props)` and `offset_at(text, x, props)` map between a byte and a pixel. A backend
that fills the optional `offset_x` and `index_at` answers them from its own shaped-run cache, which
is both cheaper and correct across a ligature; without them Loom measures prefixes.

`Props.text_align` places the text across the node and `Props.text_align_v` places it down the node.
Both inherit. `justify` and `align` place a node's *children*, so they say nothing about its own
text: a label in a box taller than one line needs `text_align_v = .Center`.

## Scrolling

A node scrolls when it has `.Scroll_X` / `.Scroll_Y` or an `overflow` of `.Scroll` / `.Auto`, and it
gets its scrollbars from that alone — `scroll()` is only the usual set of props around it. The bars
are an absolute pass-through overlay, out of flow, so they never enter `content`. `.No_Bars` keeps
the scrolling and drops them.

The wheel goes to the innermost scrollable node under the pointer with room left, and bubbles up
when there is none. A node with `.Wheel` instead takes the unscaled delta in `Interaction.wheel` and
scrolls nothing — for a view that owns its own offset, such as a virtualised text editor. It reports
even when nothing would move, so a Ctrl + wheel at the end of the content still arrives. Its own
offset then moves only through `set_scroll(node, axis, v)`.

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
