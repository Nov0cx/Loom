package loom

Viewport :: struct {
	handle: Viewport_Handle,
	rect:   Rect,
	node:   ^Node,
	dock:   ^Dock_Node,
	space:  ^Dock_Space,
}

Viewport_Draw :: struct {
	handle: Viewport_Handle,
	rect:   Rect,
	list:   Draw_List,
}

end_frame_viewports :: proc() -> []Viewport_Draw {
	ctx := ctx_of()
	return ctx.viewport_draws[:]
}

viewport_count :: proc() -> int {
	return len(ctx_of().viewports)
}

@(private)
poll_viewports :: proc(ctx: ^Context) {
	ctx.pointer_viewport = nil
	if len(ctx.viewports) == 0 {
		return
	}
	ops := viewport_ops(ctx)
	if ops == nil {
		return
	}

	for i := len(ctx.viewports) - 1; i >= 0; i -= 1 {
		if i >= len(ctx.viewports) {
			continue
		}
		v := ctx.viewports[i]
		ev := ops.poll(v.handle, ctx.cfg.backend.user)
		if ev.rect.w > 0 && ev.rect.h > 0 {
			v.rect = ev.rect
		}
		if ev.closed {
			viewport_release(ctx, v)
			continue
		}
		if !ev.focused || !ev.has_mouse {
			continue
		}

		ctx.pointer_viewport = v
		ctx.input.mouse = ev.mouse - Vec2{v.rect.x, v.rect.y}
		ctx.input.wheel = ev.wheel
		ctx.input.mouse_down = ev.mouse_down
		ctx.input.mouse_pressed = ev.mouse_pressed
		ctx.input.mouse_released = ev.mouse_released
		ctx.input.keys_down = ev.keys_down
		ctx.input.keys_pressed = ev.keys_pressed
		ctx.input.mods = ev.mods
		ctx.input.text = ev.text
	}
}

@(private)
emit_viewports :: proc(ctx: ^Context) {
	clear(&ctx.viewport_draws)
	for v in ctx.viewports {
		if v.node == nil || v.rect.w <= 0 || v.rect.h <= 0 {
			continue
		}
		list, _ := emit_order(ctx, paint_order_viewport(ctx, v), false)
		append(&ctx.viewport_draws, Viewport_Draw{handle = v.handle, rect = v.rect, list = list})
	}
}

@(private)
free_viewports :: proc(ctx: ^Context) {
	ops := viewport_ops(ctx)
	for v in ctx.viewports {
		if ops != nil {
			ops.destroy(v.handle, ctx.cfg.backend.user)
		}
		free(v, ctx.allocator)
	}
	delete(ctx.viewports)
	ctx.viewports = {}
	delete(ctx.viewport_draws)
	ctx.viewport_draws = {}
	ctx.pointer_viewport = nil
}

@(private)
viewport_forget :: proc(ctx: ^Context, v: ^Viewport) {
	for i in 0 ..< len(ctx.viewports) {
		if ctx.viewports[i] == v {
			ordered_remove(&ctx.viewports, i)
			break
		}
	}
	if ctx.pointer_viewport == v {
		ctx.pointer_viewport = nil
	}
	if ops := viewport_ops(ctx); ops != nil {
		ops.destroy(v.handle, ctx.cfg.backend.user)
	}
	free(v, ctx.allocator)
}

@(private)
viewport_drop :: proc(ctx: ^Context, v: ^Viewport) {
	if v == nil {
		return
	}
	if v.dock != nil {
		v.dock.viewport = nil
	}
	viewport_forget(ctx, v)
}

@(private)
viewport_release :: proc(ctx: ^Context, v: ^Viewport) {
	if v == nil {
		return
	}
	sp := v.space
	tn := v.dock
	if tn != nil {
		tn.viewport = nil
		if sp != nil {
			dest := dock_largest_tabs(sp.root)
			if dest == nil {
				dest = dock_ensure_root(ctx, sp)
			}
			for tab in tn.tabs {
				append(&dest.tabs, tab)
			}
			clear(&tn.tabs)
			dest.active = clamp(dest.active, 0, max(len(dest.tabs) - 1, 0))
			dock_detached_forget(sp, tn)
			dock_free_node(ctx, tn)
		}
	}
	viewport_forget(ctx, v)
	mark_dirty(ctx)
}

@(private)
dock_detached_forget :: proc(sp: ^Dock_Space, n: ^Dock_Node) {
	for i in 0 ..< len(sp.detached) {
		if sp.detached[i] == n {
			ordered_remove(&sp.detached, i)
			return
		}
	}
}

@(private)
dock_detach_tab :: proc(
	ctx: ^Context,
	sp: ^Dock_Space,
	from: ^Dock_Node,
	idx: int,
	at: Vec2,
) -> bool {
	ops := viewport_ops(ctx)
	if ops == nil || sp.cfg.mode != .Detachable {
		return false
	}

	size := DOCK_FLOAT_SIZE
	if from.rect.w > 0 && from.rect.h > 0 {
		size = {from.rect.w, from.rect.h}
	}
	r := Rect{at.x, at.y, size.x, size.y}

	title := from.tabs[idx].title
	h := ops.create(title, r, ctx.cfg.backend.user)
	if h == 0 {
		return false
	}

	v, err := new(Viewport, ctx.allocator)
	assert(err == nil, "loom: out of memory allocating a viewport")
	v.handle = h
	v.rect = r
	v.space = sp
	append(&ctx.viewports, v)

	tn := dock_new_node(ctx, sp, .Tabs)
	tn.viewport = v
	v.dock = tn
	append(&sp.detached, tn)

	tab := dock_take_tab(ctx, from, idx)
	dock_add_tab(ctx, tn, tab)
	dock_collapse(ctx, sp, from)
	mark_dirty(ctx)
	return true
}

@(private)
dock_restore_viewport :: proc(ctx: ^Context, sp: ^Dock_Space, n: ^Dock_Node, spec: string) {
	ops := viewport_ops(ctx)
	if ops == nil {
		return
	}
	r, ok := dock_rect_of(spec)
	if !ok || r.w <= 0 || r.h <= 0 {
		return
	}
	title := len(n.tabs) > 0 ? n.tabs[0].title : sp.id
	h := ops.create(title, r, ctx.cfg.backend.user)
	if h == 0 {
		return
	}

	v, err := new(Viewport, ctx.allocator)
	assert(err == nil, "loom: out of memory allocating a viewport")
	v.handle = h
	v.rect = r
	v.space = sp
	v.dock = n
	append(&ctx.viewports, v)
	n.viewport = v
}
