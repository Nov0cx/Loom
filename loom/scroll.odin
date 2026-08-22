package loom

import "core:math"

@(private)
Scroll_Tween :: struct {
	from, to: Vec2,
	elapsed:  f32,
	dur:      f32,
	ease:     Ease,
	axes:     [Axis]bool,
	active:   bool,
}

@(private)
node_scrollable :: proc(n: ^Node) -> (out: [Axis]bool) {
	out[.X] = .Scroll_X in n.flags || n.computed.overflow[0] == .Scroll || n.computed.overflow[0] == .Auto
	out[.Y] = .Scroll_Y in n.flags || n.computed.overflow[1] == .Scroll || n.computed.overflow[1] == .Auto
	return
}

@(private)
content_box :: proc(n: ^Node) -> Vec2 {
	e := inner_edges(&n.computed)
	return {max(n.rect.w - e.l - e.r, 0), max(n.rect.h - e.t - e.b, 0)}
}

@(private)
scroll_limit :: proc(n: ^Node) -> Vec2 {
	box := content_box(n)
	return {max(n.content.x - box.x, 0), max(n.content.y - box.y, 0)}
}

@(private)
find_tween :: proc(n: ^Node) -> ^Scroll_Tween {
	return (^Scroll_Tween)(state_find(n, Scroll_Tween))
}

@(private)
route_wheel :: proc(ctx: ^Context) {
	w := ctx.input.wheel
	if .Shift in ctx.input.mods && w.x == 0 {
		w = {w.y, 0}
	}
	w *= ctx.cfg.scroll_speed
	if w.x == 0 && w.y == 0 {
		return
	}

	start := node_alive(ctx, ctx.scroll_id)
	if start == nil {
		return
	}

	for a in Axis {
		i := int(a)
		if w[i] == 0 {
			continue
		}
		for n := start; n != nil; n = n.parent {
			if !node_scrollable(n)[a] {
				continue
			}
			lim := scroll_limit(n)[i]
			if lim <= SCROLL_EPS {
				continue
			}
			room := w[i] > 0 ? lim - n.scroll[i] : n.scroll[i]
			if room <= SCROLL_EPS {
				continue
			}

			take := clamp(w[i], -n.scroll[i], lim - n.scroll[i])
			n.scroll[i] += take
			n.scroll_want[i] = n.scroll[i]
			if !ctx.cfg.no_scroll_inertia {
				n.scroll_vel[i] += take * ctx.cfg.scroll_inertia
			}
			if tw := find_tween(n); tw != nil {
				tw.active = false
			}
			ctx.wheel_id[a] = n.id
			ctx.wheel_amount[a] = take
			break
		}
	}
}

@(private)
step_scroll :: proc(ctx: ^Context, n: ^Node) {
	if tw := find_tween(n); tw != nil && tw.active {
		tw.elapsed += ctx.input.dt
		n.scroll_vel = {}
		if tw.elapsed >= tw.dur {
			for a in Axis {
				if tw.axes[a] {
					n.scroll[int(a)] = tw.to[int(a)]
				}
			}
			tw.active = false
		} else {
			k := ease_at(tw.ease, tw.dur > 0 ? tw.elapsed / tw.dur : 1)
			for a in Axis {
				i := int(a)
				if tw.axes[a] {
					n.scroll[i] = tw.from[i] + (tw.to[i] - tw.from[i]) * k
				}
			}
			ctx.scrolling = true
		}
		n.scroll_want = n.scroll
		return
	}

	if n.scroll_vel.x == 0 && n.scroll_vel.y == 0 {
		return
	}
	if ctx.cfg.no_scroll_inertia {
		n.scroll_vel = {}
		return
	}

	for a in Axis {
		i := int(a)
		if abs(n.scroll[i] - n.scroll_want[i]) > SCROLL_EPS {
			n.scroll_vel[i] = 0
		}
		if n.scroll_vel[i] == 0 {
			continue
		}
		n.scroll_vel[i] *= math.pow(ctx.cfg.scroll_damping, ctx.input.dt)
		if abs(n.scroll_vel[i]) < SCROLL_STOP {
			n.scroll_vel[i] = 0
			continue
		}
		n.scroll[i] += n.scroll_vel[i] * ctx.input.dt
		ctx.scrolling = true
	}
	n.scroll_want = n.scroll
}

scroll_to :: proc(id: Id, animated := true) {
	ctx := ctx_of()
	n := node_alive(ctx, id)
	if n == nil {
		return
	}

	sc := n.parent
	for ; sc != nil; sc = sc.parent {
		if node_scrollable(sc) != {} {
			break
		}
	}
	if sc == nil {
		return
	}

	can := node_scrollable(sc)
	box := content_box(sc)
	lim := scroll_limit(sc)
	e := inner_edges(&sc.computed)
	org := Vec2{sc.rect.x + e.l, sc.rect.y + e.t}
	pos := Vec2{n.rect.x, n.rect.y}
	size := Vec2{n.rect.w, n.rect.h}

	to := sc.scroll
	for a in Axis {
		i := int(a)
		if !can[a] {
			continue
		}
		lo := pos[i] - org[i] + sc.scroll[i]
		hi := lo + size[i]
		if lo < sc.scroll[i] {
			to[i] = lo
		} else if hi > sc.scroll[i] + box[i] {
			to[i] = hi - box[i]
		}
		to[i] = clamp(to[i], 0, lim[i])
	}
	if to == sc.scroll {
		return
	}

	sc.scroll_vel = {}
	if !animated {
		sc.scroll = to
		sc.scroll_want = to
		if tw := find_tween(sc); tw != nil {
			tw.active = false
		}
		return
	}

	tw := (^Scroll_Tween)(
		state_raw(ctx, sc, Scroll_Tween, size_of(Scroll_Tween), align_of(Scroll_Tween)),
	)
	tw.from = sc.scroll
	tw.to = to
	tw.elapsed = 0
	tw.dur = ctx.cfg.scroll_to_dur
	tw.ease = .Out_Cubic
	tw.axes = can
	tw.active = true
}
