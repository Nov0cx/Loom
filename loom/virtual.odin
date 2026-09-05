package loom

// Rows built past the viewport on each side, so a scroll of one frame never
// shows a gap.
VIRTUAL_OVERSCAN :: 2

@(private)
Virtual_State :: struct {
	tail: f32,
}

@(private)
scroll_ancestor :: proc(n: ^Node) -> ^Node {
	for p := n; p != nil; p = p.parent {
		if p.flags & {.Scroll_X, .Scroll_Y} != {} || node_scrollable(p) != {} {
			return p
		}
	}
	return nil
}

// The rows of a `count` by `row_h` list that the scroll viewport shows, from the
// previous frame's offset. It opens no node, so a caller that places its own
// rows can ask the question on its own. Before the first layout there is no
// viewport yet, and the window covers the whole window height instead.
virtual_window :: proc(
	count: int,
	row_h: f32,
	overscan := VIRTUAL_OVERSCAN,
) -> (
	first, last: int,
) {
	if count <= 0 || row_h <= 0 {
		return 0, 0
	}

	ctx := ctx_of()
	view := ctx.input.viewport.y
	off := f32(0)
	if sc := scroll_ancestor(current()); sc != nil {
		off = sc.scroll.y
		if h := inner_box(sc).y; h > 0 {
			view = h
		}
	}

	first = clamp(int(off / row_h) - overscan, 0, count)
	last = clamp(int((off + view) / row_h) + 1 + overscan, first, count)
	return
}

// Opens a list of `count` rows of `row_h` that builds only the visible ones. The
// node is sized for the whole list, so the scrollbar stays honest, and spacers
// hold the place of the rows above and below. Build the returned window, then
// call `end_virtual`.
//
// Rows must be one height. Soft-wrapped text still fits: a wrapped line is more
// rows of the same height, not a taller one.
virtual :: proc(
	count: int,
	row_h: f32,
	el: Element = {},
	loc := #caller_location,
) -> (
	first, last: int,
) {
	first, last = virtual_window(count, row_h)

	e := el
	e.props.dir = .Column
	if e.props.w == nil {
		e.props.w = Grow(1)
	}
	e.props.h = Px(f32(max(count, 0)) * max(row_h, 0))
	begin(e, loc)

	st := state(Virtual_State)
	st.tail = f32(count - last) * row_h

	if head := f32(first) * row_h; head > 0 {
		leaf({key = "loom.virtual.head", props = {h = Px(head)}})
	}
	return
}

// Closes a `virtual` list.
end_virtual :: proc() {
	if n := current(); n != nil {
		st := state_of(n, Virtual_State)
		if st.tail > 0 {
			leaf({key = "loom.virtual.tail", props = {h = Px(st.tail)}})
		}
	}
	end()
}
