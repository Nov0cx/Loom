package loom

@(private)
node_alive :: proc(ctx: ^Context, id: Id) -> ^Node {
	if id == 0 {
		return nil
	}
	n, ok := ctx.nodes[id]
	return n if ok else nil
}

@(private)
hit_target :: proc(n: ^Node) -> bool {
	if n.flags & {.Clickable, .Focusable, .Draggable, .Scroll_X, .Scroll_Y} != {} {
		return true
	}
	return node_scrollable(n) != {}
}

@(private)
hit_test :: proc(ctx: ^Context, order: []Paint_Entry, p: Vec2) -> (hovered, scroller: Id) {
	#reverse for e in order {
		n := e.node
		if !rect_contains(n.rect, p) || !rect_contains(e.clip, p) {
			continue
		}
		if .Disabled in n.state {
			continue
		}
		if scroller == 0 && node_scrollable(n) != {} {
			scroller = n.id
		}
		if hovered == 0 && .Pass_Through not_in n.flags && hit_target(n) {
			hovered = n.id
		}
		if hovered != 0 && scroller != 0 {
			break
		}
	}
	return
}

@(private)
forget_pruned :: proc(ctx: ^Context) {
	if node_alive(ctx, ctx.focus_id) == nil {
		ctx.focus_id = 0
	}
	if node_alive(ctx, ctx.capture_id) == nil {
		ctx.capture_id = 0
		ctx.capture_implicit = false
	}
	if node_alive(ctx, ctx.drag_id) == nil {
		ctx.drag_id = 0
		ctx.drag_active = false
	}
	if node_alive(ctx, ctx.activate_id) == nil {
		ctx.activate_id = 0
	}
	if node_alive(ctx, ctx.last_click_id) == nil {
		ctx.last_click_id = 0
		ctx.click_count = 0
	}
	if node_alive(ctx, ctx.hovered_id) == nil {
		ctx.hovered_id = 0
	}
	if node_alive(ctx, ctx.scroll_id) == nil {
		ctx.scroll_id = 0
	}
	for b in Mouse_Button {
		if node_alive(ctx, ctx.press_id[b]) == nil {
			ctx.press_id[b] = 0
		}
	}
}

@(private)
clear_frame_results :: proc(ctx: ^Context) {
	ctx.pressed_id = {}
	ctx.released_id = {}
	ctx.clicked_id = 0
	ctx.right_clicked_id = 0
	ctx.double_clicked_id = 0
	ctx.drag_delta = {}
	ctx.wheel_id = {}
	ctx.wheel_amount = {}
}

@(private)
is_in_subtree :: proc(ctx: ^Context, anc: Id, n: ^Node) -> bool {
	if anc == 0 {
		return false
	}
	for p := n; p != nil; p = p.parent {
		if p.id == anc {
			return true
		}
	}
	return false
}

@(private)
step_mouse :: proc(ctx: ^Context, hit: Id) {
	delta := ctx.have_input ? ctx.input.mouse - ctx.prev_mouse : Vec2{}

	for b in Mouse_Button {
		if b in ctx.input.mouse_pressed {
			ctx.press_id[b] = hit
			ctx.press_pos[b] = ctx.input.mouse
			ctx.pressed_id[b] = hit
			if b == .Left {
				press_left(ctx, hit)
			}
		}

		if b in ctx.input.mouse_released {
			ctx.released_id[b] = hit
			if ctx.press_id[b] != 0 && ctx.press_id[b] == hit {
				switch b {
				case .Left:
					ctx.clicked_id = hit
					step_double_click(ctx, hit)
				case .Right:
					ctx.right_clicked_id = hit
				case .Middle:
				}
			}
			ctx.press_id[b] = 0
			if b == .Left {
				ctx.drag_id = 0
				ctx.drag_active = false
				if ctx.capture_implicit {
					ctx.capture_id = 0
					ctx.capture_implicit = false
				}
			}
		}
	}

	if ctx.drag_id != 0 && .Left in ctx.input.mouse_down {
		if ctx.drag_active {
			ctx.drag_delta = delta
		} else {
			d := ctx.input.mouse - ctx.drag_start
			if abs(d.x) >= DRAG_SLOP || abs(d.y) >= DRAG_SLOP {
				ctx.drag_active = true
				ctx.drag_delta = d
			}
		}
	}
}

@(private)
press_left :: proc(ctx: ^Context, hit: Id) {
	n := node_alive(ctx, hit)
	if n != nil && .Draggable in n.flags {
		ctx.drag_id = hit
		ctx.drag_active = false
		ctx.drag_start = ctx.input.mouse
		ctx.capture_id = hit
		ctx.capture_implicit = true
	}

	if n == nil {
		ctx.focus_id = 0
		return
	}
	if .Focusable in n.flags {
		ctx.focus_id = hit
		return
	}
	if !is_in_subtree(ctx, ctx.focus_id, n) {
		ctx.focus_id = 0
	}
}

@(private)
step_double_click :: proc(ctx: ^Context, hit: Id) {
	m := ctx.input.mouse
	same := ctx.last_click_id == hit
	in_time := ctx.time - ctx.last_click_time <= f64(ctx.cfg.double_click)
	near :=
		abs(m.x - ctx.last_click_pos.x) <= CLICK_SLOP &&
		abs(m.y - ctx.last_click_pos.y) <= CLICK_SLOP

	if same && in_time && near {
		ctx.click_count += 1
	} else {
		ctx.click_count = 1
	}
	if ctx.click_count == 2 {
		ctx.double_clicked_id = hit
	}
	ctx.last_click_id = hit
	ctx.last_click_time = ctx.time
	ctx.last_click_pos = m
}

@(private)
focus_order :: proc(ctx: ^Context) -> []^Node {
	out := make([dynamic]^Node, 0, 16, ctx.frame_allocator)
	if ctx.root != nil {
		focus_collect(ctx.root, &out)
	}
	return out[:]
}

@(private)
focus_collect :: proc(n: ^Node, out: ^[dynamic]^Node) {
	if .Disabled in n.state {
		return
	}
	if .Focusable in n.flags {
		append(out, n)
	}
	for c := n.first_child; c != nil; c = c.next {
		focus_collect(c, out)
	}
}

@(private)
step_focus_keys :: proc(ctx: ^Context) {
	if .Escape in ctx.input.keys_pressed {
		ctx.focus_id = 0
		return
	}
	if .Tab not_in ctx.input.keys_pressed {
		return
	}

	list := focus_order(ctx)
	if len(list) == 0 {
		ctx.focus_id = 0
		return
	}

	back := .Shift in ctx.input.mods
	idx := -1
	for n, i in list {
		if n.id == ctx.focus_id {
			idx = i
			break
		}
	}

	next: int
	if idx < 0 {
		next = back ? len(list) - 1 : 0
	} else {
		next = back ? (idx - 1 + len(list)) % len(list) : (idx + 1) % len(list)
	}
	ctx.focus_id = list[next].id
}

@(private)
step_activate :: proc(ctx: ^Context) {
	if ctx.activate_id != 0 {
		if .Space not_in ctx.input.keys_down && .Enter not_in ctx.input.keys_down {
			ctx.released_id[.Left] = ctx.activate_id
			ctx.clicked_id = ctx.activate_id
			ctx.activate_id = 0
		}
		return
	}

	n := node_alive(ctx, ctx.focus_id)
	if n == nil {
		return
	}
	if .Clickable not_in n.flags || .Text_Input in n.flags || .Disabled in n.state {
		return
	}

	fresh := ctx.input.keys_pressed - ctx.prev_keys
	if .Space in fresh || .Enter in fresh {
		ctx.activate_id = ctx.focus_id
		ctx.pressed_id[.Left] = ctx.focus_id
	}
}

@(private)
active_id :: proc(ctx: ^Context) -> Id {
	if .Left in ctx.input.mouse_down {
		return ctx.press_id[.Left]
	}
	return ctx.activate_id
}

@(private)
apply_input_states :: proc(ctx: ^Context) {
	ctx.scrolling = false
	for _, n in ctx.nodes {
		n.input_state = {}
		step_scroll(ctx, n)
	}
	if n := node_alive(ctx, ctx.hovered_id); n != nil {
		n.input_state += {.Hover}
	}
	if n := node_alive(ctx, ctx.focus_id); n != nil {
		n.input_state += {.Focus}
	}
	if n := node_alive(ctx, active_id(ctx)); n != nil {
		n.input_state += {.Active}
	}
}

@(private)
recompute_states :: proc(ctx: ^Context) {
	ctx.time += f64(ctx.input.dt)
	forget_pruned(ctx)
	if ctx.focus_next_set {
		ctx.focus_id = ctx.focus_next
		ctx.focus_next = 0
		ctx.focus_next_set = false
	}

	clear_frame_results(ctx)

	if ctx.root != nil {
		hit, scroller: Id
		if ctx.capture_id != 0 {
			hit = ctx.capture_id
		} else {
			hit, scroller = hit_test(ctx, paint_order(ctx, ctx.root), ctx.input.mouse)
		}
		ctx.hovered_id = hit
		ctx.scroll_id = scroller

		step_mouse(ctx, hit)
		step_focus_keys(ctx)
		step_activate(ctx)
		route_wheel(ctx)
	} else {
		ctx.hovered_id = 0
		ctx.scroll_id = 0
	}

	apply_input_states(ctx)
	ctx.prev_mouse = ctx.input.mouse
	ctx.prev_keys = ctx.input.keys_down
	ctx.have_input = true
}

@(private)
flush_cursor :: proc(ctx: ^Context) {
	c := ctx.cursor
	if !ctx.cursor_forced {
		c = .Default
		if n := node_alive(ctx, ctx.hovered_id); n != nil {
			c = n.computed.cursor
		}
	}
	ctx.cursor = .Default
	ctx.cursor_forced = false

	if ctx.cursor_valid && ctx.cursor_last == c {
		return
	}
	ctx.cursor_last = c
	ctx.cursor_valid = true
	if ctx.cfg.backend.set_cursor != nil {
		ctx.cfg.backend.set_cursor(c, ctx.cfg.backend.user)
	}
}

hovered :: proc() -> ^Node {
	ctx := ctx_of()
	return node_alive(ctx, ctx.hovered_id)
}

focused :: proc() -> ^Node {
	ctx := ctx_of()
	return node_alive(ctx, ctx.focus_id)
}

set_focus :: proc(id: Id) {
	ctx := ctx_of()
	ctx.focus_next = id
	ctx.focus_next_set = true
}

capture_mouse :: proc(id: Id) {
	ctx := ctx_of()
	ctx.capture_id = id
	ctx.capture_implicit = false
}

set_cursor :: proc(c: Cursor) {
	ctx := ctx_of()
	ctx.cursor = c
	ctx.cursor_forced = true
}

wants_mouse :: proc() -> bool {
	ctx := ctx_of()
	return ctx.hovered_id != 0 || ctx.scroll_id != 0 || ctx.capture_id != 0
}

wants_keyboard :: proc() -> bool {
	ctx := ctx_of()
	n := node_alive(ctx, ctx.focus_id)
	return n != nil && .Text_Input in n.flags
}
