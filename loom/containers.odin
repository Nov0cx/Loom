package loom

import "base:runtime"

BAR_W :: f32(10)
BAR_PAD :: f32(2)
BAR_MIN_THUMB :: f32(24)
BAR_RADIUS :: f32(4)
BAR_EPS :: f32(0.5)

POPUP_GAP :: f32(4)
POPUP_PAD :: f32(4)
POPUP_RADIUS :: f32(8)
POPUP_DUR :: f32(0.1)

TOOLTIP_DELAY :: f32(0.5)
TOOLTIP_RADIUS :: f32(6)
TOOLTIP_MAX_W :: f32(320)
TOOLTIP_OFFSET :: Vec2{14, 20}

BARS_KEY :: "loom.bars"

@(private)
Bar_State :: struct {
	grab: f32,
}

@(private)
Tooltip_Timer :: struct {
	hover_t: f32,
}

scroll :: proc(el: Element = {}, loc := #caller_location) -> Interaction {
	ctx := ctx_of(loc)
	e := Element {
		flags = {.Clip, .Scroll_Y},
		props = {w = Grow(1), h = Grow(1), dir = .Column, position = .Relative},
	}
	merge_element(&e, el, loc)

	it := begin(e, loc)
	scroll_bars(ctx, it.node, loc)
	return it
}

@(private)
scroll_bars :: proc(ctx: ^Context, n: ^Node, loc: runtime.Source_Code_Location) {
	lim := scroll_limit(n)
	can := node_scrollable(n)
	vert := can[.Y] && lim.y > BAR_EPS
	horz := can[.X] && lim.x > BAR_EPS
	if !vert && !horz {
		return
	}

	box := content_box(n)

	begin(
		{
			key = BARS_KEY,
			flags = {.Pass_Through},
			props = {
				position = .Absolute,
				z = 1,
				w = Pct(100),
				h = Pct(100),
				dir = .Column,
			},
		},
		loc,
	)

	begin({key = "vrow", flags = {.Pass_Through}, props = {w = STRETCH, h = Grow(1), dir = .Row}}, loc)
	if vert {
		leaf({key = "vgap", flags = {.Pass_Through}, props = {w = Grow(1), h = STRETCH}}, loc)
		scroll_bar(ctx, n, .Y, box.y, lim.y, box.y - (horz ? BAR_W : 0), loc)
	}
	end()

	if horz {
		begin({key = "hrow", flags = {.Pass_Through}, props = {w = STRETCH, h = Px(BAR_W), dir = .Row}}, loc)
		scroll_bar(ctx, n, .X, box.x, lim.x, box.x - (vert ? BAR_W : 0), loc)
		if vert {
			leaf({key = "corner", flags = {.Pass_Through}, props = {w = Px(BAR_W), h = STRETCH}}, loc)
		}
		end()
	}

	end()
}

@(private)
scroll_bar :: proc(
	ctx: ^Context,
	n: ^Node,
	ax: Axis,
	box, lim, bar_len: f32,
	loc: runtime.Source_Code_Location,
) {
	t := &ctx.theme
	inner := max(bar_len - BAR_PAD * 2, 0)
	total := box + lim
	frac := total > 0 ? clamp(box / total, 0, 1) : 1
	thumb := clamp(inner * frac, min(BAR_MIN_THUMB, inner), inner)
	travel := max(inner - thumb, 0)
	off := ax == .X ? n.scroll.x : n.scroll.y
	pos := lim > 0 ? clamp(off / lim, 0, 1) : 0

	bar := Element {
		key   = ax == .X ? "hbar" : "vbar",
		flags = {.Clickable},
		props = {bg = fade(t.scrollbar, 0.25), pad = all(BAR_PAD)},
	}
	th := Element {
		key = ax == .X ? "hthumb" : "vthumb",
		flags = {.Draggable},
		props = {bg = t.scrollbar, radius = rad(BAR_RADIUS)},
		hover = {bg = t.scrollbar_hover},
	}
	pre := Element{key = "pre"}
	post := Element{key = "post"}

	if ax == .X {
		bar.props.w, bar.props.h, bar.props.dir = STRETCH, Px(BAR_W), .Row
		th.props.w, th.props.h = Px(thumb), STRETCH
		pre.props.w, post.props.w = Px(travel * pos), Grow(1)
	} else {
		bar.props.w, bar.props.h, bar.props.dir = Px(BAR_W), STRETCH, .Column
		th.props.w, th.props.h = STRETCH, Px(thumb)
		pre.props.h, post.props.h = Px(travel * pos), Grow(1)
	}

	bi := begin(bar, loc)
	leaf(pre, loc)
	ti := leaf(th, loc)
	leaf(post, loc)
	end()

	bs := state_of(ti.node, Bar_State)

	if ti.pressed {
		bs.grab = off
	}
	if ti.dragging {
		room := max(travel, 1)
		start := ax == .X ? ti.drag_start.x : ti.drag_start.y
		now := ax == .X ? ctx.input.mouse.x : ctx.input.mouse.y
		set_scroll(n, ax, clamp(bs.grab + (now - start) / room * lim, 0, lim))
	} else if bi.clicked {
		back := ax == .X ? ctx.input.mouse.x < ti.node.rect.x : ctx.input.mouse.y < ti.node.rect.y
		set_scroll(n, ax, clamp(off + (back ? -box : box), 0, lim))
	}
}

@(private)
set_scroll :: proc(n: ^Node, ax: Axis, v: f32) {
	if ax == .X {
		n.scroll.x = v
	} else {
		n.scroll.y = v
	}
	n.scroll_want = n.scroll
	n.scroll_vel = {}
	if tw := find_tween(n); tw != nil {
		tw.active = false
	}
}

popup :: proc(open: ^bool, anchor: Id, el: Element = {}, loc := #caller_location) -> bool {
	ctx := ctx_of(loc)
	if !open^ {
		return false
	}

	id := el.key != "" ? hash_string(ctx.id_seed, el.key) : hash_loc(ctx.id_seed, loc)

	if key_pressed(.Escape) {
		consume_key(.Escape)
		open^ = false
		return false
	}

	if .Left in ctx.input.mouse_pressed {
		hit := node_alive(ctx, ctx.press_id[.Left])
		inside := hit != nil && (is_in_subtree(ctx, id, hit) || is_in_subtree(ctx, anchor, hit))
		if !inside {
			open^ = false
			return false
		}
	}

	a := node_alive(ctx, anchor)
	if a == nil {
		open^ = false
		return false
	}

	vp := ctx.input.viewport
	x := a.rect.x
	y := a.rect.y + a.rect.h + POPUP_GAP
	prev := node_alive(ctx, id)
	if prev != nil {
		if y + prev.rect.h > vp.y {
			y = a.rect.y - prev.rect.h - POPUP_GAP
		}
		if x + prev.rect.w > vp.x {
			x = vp.x - prev.rect.w
		}
		x, y = max(x, 0), max(y, 0)
	}

	t := &ctx.theme
	e := Element {
		flags = {.Floating, .Clickable},
		props = {
			position = .Fixed,
			inset = {l = x, t = y},
			w = FIT,
			h = FIT,
			dir = .Column,
			pad = all(POPUP_PAD),
			bg = t.raised,
			radius = rad(POPUP_RADIUS),
			border = {width = all(1), color = t.border},
			shadow = {offset = {0, 4}, blur = 16, color = t.shadow},
			opacity = prev != nil ? 1 : 0,
		},
		transition = {props = {.Opacity}, dur = POPUP_DUR},
		state = {.Open},
	}
	merge_element(&e, el, loc)
	begin(e, loc)
	return true
}

tooltip :: proc(
	text: string,
	for_id: Id,
	delay: f32 = TOOLTIP_DELAY,
	el: Element = {},
	loc := #caller_location,
) -> Interaction {
	ctx := ctx_of(loc)
	a := node_alive(ctx, for_id)
	if a == nil || text == "" {
		return {}
	}

	tt := state_of(a, Tooltip_Timer)
	hot := is_in_subtree(ctx, for_id, node_alive(ctx, ctx.hovered_id))
	if hot && ctx.input.mouse_down == {} {
		tt.hover_t += ctx.input.dt
	} else {
		tt.hover_t = 0
	}
	if tt.hover_t < delay {
		if tt.hover_t > 0 {
			request_frame(loc)
		}
		return {}
	}

	push_id_int(i64(for_id))
	defer pop_id(loc)

	id := el.key != "" ? hash_string(ctx.id_seed, el.key) : hash_loc(ctx.id_seed, loc)
	prev := node_alive(ctx, id)

	vp := ctx.input.viewport
	p := ctx.input.mouse + TOOLTIP_OFFSET
	if prev != nil {
		p.x = clamp(p.x, 0, max(vp.x - prev.rect.w, 0))
		p.y = clamp(p.y, 0, max(vp.y - prev.rect.h, 0))
	}

	t := &ctx.theme
	e := Element {
		text = text,
		flags = {.Floating, .Pass_Through},
		props = {
			position = .Fixed,
			inset = {l = p.x, t = p.y},
			w = FIT,
			h = FIT,
			max_w = TOOLTIP_MAX_W,
			pad = xy(8, 5),
			bg = t.overlay,
			color = t.text,
			radius = rad(TOOLTIP_RADIUS),
			border = {width = all(1), color = t.border},
			shadow = {offset = {0, 2}, blur = 12, color = t.shadow},
			text_wrap = .Words,
			opacity = prev != nil ? 1 : 0,
		},
	}
	merge_element(&e, el, loc)
	return leaf(e, loc)
}
