package loom

import "core:math"

MAX_COMPONENTS :: 8

SPRING_STIFFNESS :: f32(170)
SPRING_DAMPING :: f32(26)
SPRING_STEP :: f32(1.0 / 240.0)
SPRING_EPS_X :: f32(0.001)
SPRING_EPS_V :: f32(0.01)

Prop_Val :: struct {
	v:     [MAX_COMPONENTS]f32,
	count: u8,
	tag:   u8,
	lerp:  bool,
}

@(private)
Anim_Slot :: struct {
	a:       [MAX_COMPONENTS]f32,
	to:      [MAX_COMPONENTS]f32,
	elapsed: f32,
	tag:     u8,
	count:   u8,
	active:  bool,
}

@(private)
Anim :: struct {
	slots: [Prop]Anim_Slot,
}

ease_at :: proc(e: Ease, x: f32) -> f32 {
	t := clamp(x, 0, 1)
	switch e {
	case .Linear:
		return t
	case .Out_Quad:
		u := 1 - t
		return 1 - u * u
	case .In_Out_Quad:
		if t < 0.5 {
			return 2 * t * t
		}
		u := 1 - t
		return 1 - 2 * u * u
	case .Out_Cubic:
		u := 1 - t
		return 1 - u * u * u
	case .Out_Back:
		C1 :: f32(1.70158)
		C3 :: C1 + 1
		u := t - 1
		return 1 + C3 * u * u * u + C1 * u * u
	case .Spring:
		return t
	}
	return t
}

animating :: proc() -> bool {
	ctx := ctx_of()
	return ctx.animating || ctx.scrolling
}

@(private)
spread_color :: proc(c: Color, out: ^[MAX_COMPONENTS]f32, at: int) {
	for i in 0 ..< 4 {
		out[at + i] = f32(c[i])
	}
}

@(private)
gather_color :: proc(v: ^[MAX_COMPONENTS]f32, at: int) -> Color {
	c: Color
	for i in 0 ..< 4 {
		c[i] = u8(clamp(v[at + i] + 0.5, 0, 255))
	}
	return c
}

@(private)
prop_decode :: proc(p: ^Props, prop: Prop) -> (out: Prop_Val) {
	q := prop_ptr(p, prop)
	switch PROP_TABLE[prop].kind {
	case .F32:
		out.v[0] = (^f32)(q)^
		out.count, out.lerp = 1, true
	case .Vec2:
		v := (^Vec2)(q)^
		out.v[0], out.v[1] = v.x, v.y
		out.count, out.lerp = 2, true
	case .Edges:
		e := (^Edges)(q)^
		out.v[0], out.v[1], out.v[2], out.v[3] = e.l, e.t, e.r, e.b
		out.count, out.lerp = 4, true
	case .Radius:
		r := (^Radius)(q)^
		out.v[0], out.v[1], out.v[2], out.v[3] = r.tl, r.tr, r.br, r.bl
		out.count, out.lerp = 4, true
	case .Color:
		spread_color((^Color)(q)^, &out.v, 0)
		out.count, out.tag, out.lerp = 4, 1, true
	case .Color_Opt:
		c, has := (^Maybe(Color))(q)^.(Color)
		if !has {
			return
		}
		spread_color(c, &out.v, 0)
		out.count, out.tag, out.lerp = 4, 1, true
	case .F32_Opt:
		v, has := (^Maybe(f32))(q)^.(f32)
		out.v[0] = has ? v : 1
		out.count, out.tag, out.lerp = 1, 1, true
	case .Shadow:
		s := (^Shadow)(q)^
		out.v[0], out.v[1] = s.offset.x, s.offset.y
		out.v[2], out.v[3] = s.blur, s.spread
		spread_color(s.color, &out.v, 4)
		out.count, out.lerp = 8, true
		out.tag = s.inset ? 1 : 0
	case .Paint:
		switch v in (^Paint)(q)^ {
		case Color:
			spread_color(v, &out.v, 0)
			out.count, out.tag, out.lerp = 4, 1, true
		case Gradient:
			out.tag = 2
		}
	case .Size:
		switch v in (^Size)(q)^ {
		case Px:
			out.v[0] = f32(v)
			out.count, out.tag, out.lerp = 1, 1, true
		case Pct:
			out.v[0] = f32(v)
			out.count, out.tag, out.lerp = 1, 2, true
		case Grow:
			out.v[0] = f32(v)
			out.count, out.tag, out.lerp = 1, 3, true
		case Fit:
			out.tag = 4
		}
	}
	return
}

@(private)
prop_encode :: proc(p: ^Props, prop: Prop, val: Prop_Val) {
	q := prop_ptr(p, prop)
	v := val.v
	switch PROP_TABLE[prop].kind {
	case .F32:
		(^f32)(q)^ = v[0]
	case .Vec2:
		(^Vec2)(q)^ = {v[0], v[1]}
	case .Edges:
		(^Edges)(q)^ = {v[0], v[1], v[2], v[3]}
	case .Radius:
		(^Radius)(q)^ = {v[0], v[1], v[2], v[3]}
	case .Color:
		(^Color)(q)^ = gather_color(&v, 0)
	case .Color_Opt:
		(^Maybe(Color))(q)^ = gather_color(&v, 0)
	case .F32_Opt:
		(^Maybe(f32))(q)^ = clamp(v[0], 0, 1)
	case .Shadow:
		s := (^Shadow)(q)
		s.offset = {v[0], v[1]}
		s.blur, s.spread = v[2], v[3]
		s.color = gather_color(&v, 4)
		s.inset = val.tag == 1
	case .Paint:
		(^Paint)(q)^ = gather_color(&v, 0)
	case .Size:
		s := (^Size)(q)
		switch val.tag {
		case 1:
			s^ = Px(v[0])
		case 2:
			s^ = Pct(v[0])
		case 3:
			s^ = Grow(v[0])
		}
	}
}

@(private)
spring_step :: proc(s: ^Anim_Slot, cur: Prop_Val, dt: f32) -> (out: Prop_Val, settled: bool) {
	out = cur
	steps := max(1, int(math.ceil(dt / SPRING_STEP)))
	h := dt / f32(steps)
	settled = true
	for i in 0 ..< int(s.count) {
		x := cur.v[i]
		v := s.a[i]
		for _ in 0 ..< steps {
			acc := SPRING_STIFFNESS * (s.to[i] - x) - SPRING_DAMPING * v
			v += acc * h
			x += v * h
		}
		s.a[i] = v
		out.v[i] = x
		scale := max(f32(1), abs(s.to[i]))
		if abs(s.to[i] - x) > SPRING_EPS_X * scale || abs(v) > SPRING_EPS_V * scale {
			settled = false
		}
	}
	if settled {
		s.a = {}
	}
	return
}

@(private)
step_slot :: proc(s: ^Anim_Slot, cur: Prop_Val, tr: Transition, dt: f32) -> (out: Prop_Val, done: bool) {
	if tr.ease == .Spring {
		s.elapsed += dt
		if s.elapsed < 0 {
			return cur, false
		}
		settled: bool
		out, settled = spring_step(s, cur, dt)
		return out, settled
	}

	s.elapsed += dt
	if s.elapsed < 0 {
		return cur, false
	}
	if tr.dur <= 0 || s.elapsed >= tr.dur {
		return cur, true
	}

	k := ease_at(tr.ease, s.elapsed / tr.dur)
	out = cur
	out.count, out.tag, out.lerp = s.count, s.tag, true
	for i in 0 ..< int(s.count) {
		out.v[i] = s.a[i] + (s.to[i] - s.a[i]) * k
	}
	return out, false
}

@(private)
animate_node :: proc(ctx: ^Context, n: ^Node, resolved: Props) {
	target := resolved
	tr := n.el.transition

	live :=
		tr.props != {} &&
		(tr.dur > 0 || tr.ease == .Spring) &&
		.No_Anim not_in n.flags &&
		!n.first_frame

	if !live {
		n.computed = target
		return
	}

	an := (^Anim)(state_raw(ctx, n, Anim, size_of(Anim), align_of(Anim)))

	for prop in tr.props {
		s := &an.slots[prop]
		tv := prop_decode(&target, prop)
		cv := prop_decode(&n.computed, prop)

		if !tv.lerp || !cv.lerp || cv.tag != tv.tag {
			s.active = false
			s.to, s.tag, s.count = tv.v, tv.tag, tv.count
			continue
		}

		changed := s.to != tv.v || s.tag != tv.tag
		s.to, s.tag, s.count = tv.v, tv.tag, tv.count

		if cv.v == tv.v {
			s.active = false
			continue
		}

		if changed || !s.active {
			if tr.ease != .Spring {
				s.a = cv.v
			}
			s.elapsed = -tr.delay
			s.active = true
		}

		out, done := step_slot(s, cv, tr, ctx.input.dt)
		if done {
			s.active = false
			continue
		}
		prop_encode(&target, prop, out)
		ctx.animating = true
	}

	n.computed = target
}
