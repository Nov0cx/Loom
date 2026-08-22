package loom

Px :: distinct f32
Pct :: distinct f32
Grow :: distinct f32

Fit :: enum u8 {
	Content,
	Stretch,
}

FIT :: Fit.Content
STRETCH :: Fit.Stretch

Size :: union {
	Px,
	Pct,
	Grow,
	Fit,
}

Axis :: enum u8 {
	X,
	Y,
}

@(private)
axis_of :: proc(d: Direction) -> Axis {
	switch d {
	case .Row, .Row_Reverse:
		return .X
	case .Column, .Column_Reverse:
		return .Y
	}
	return .X
}

@(private)
cross_axis :: proc(a: Axis) -> Axis {
	return .Y if a == .X else .X
}

@(private)
axis_pair :: proc(main: Axis, main_known, cross_known: bool) -> (out: [Axis]bool) {
	out[main] = main_known
	out[cross_axis(main)] = cross_known
	return
}

@(private)
is_reverse :: proc(d: Direction) -> bool {
	return d == .Row_Reverse || d == .Column_Reverse
}

@(private)
axis_size :: proc(p: ^Props, a: Axis) -> Size {
	return p.w if a == .X else p.h
}

@(private)
axis_min :: proc(p: ^Props, a: Axis) -> f32 {
	return p.min_w if a == .X else p.min_h
}

@(private)
axis_max :: proc(p: ^Props, a: Axis) -> f32 {
	return p.max_w if a == .X else p.max_h
}

@(private)
axis_clamp :: proc(v: f32, p: ^Props, a: Axis) -> f32 {
	out := v
	lo := axis_min(p, a)
	hi := axis_max(p, a)
	if out < lo {
		out = lo
	}
	if hi > 0 && out > hi {
		out = hi
	}
	return max(out, 0)
}

@(private)
edge_lead :: proc(e: Edges, a: Axis) -> f32 {
	return e.l if a == .X else e.t
}

@(private)
edge_trail :: proc(e: Edges, a: Axis) -> f32 {
	return e.r if a == .X else e.b
}

@(private)
edge_total :: proc(e: Edges, a: Axis) -> f32 {
	return edge_lead(e, a) + edge_trail(e, a)
}

@(private)
inner_edges :: proc(p: ^Props) -> Edges {
	b := p.border.width
	return {p.pad.l + b.l, p.pad.t + b.t, p.pad.r + b.r, p.pad.b + b.b}
}

@(private)
gap_axis :: proc(g: Vec2, a: Axis) -> f32 {
	return g.x if a == .X else g.y
}

@(private)
axis_overflows :: proc(p: ^Props, flags: Flags, a: Axis) -> bool {
	if p.overflow[int(a)] != .Visible {
		return true
	}
	return a == .X ? .Scroll_X in flags : .Scroll_Y in flags
}

@(private)
size_is_stretch :: proc(s: Size) -> bool {
	v, ok := s.(Fit)
	return ok && v == .Stretch
}

@(private)
size_is_fit :: proc(s: Size) -> bool {
	v, ok := s.(Fit)
	return ok && v == .Content
}

@(private)
size_grow :: proc(s: Size) -> (f32, bool) {
	v, ok := s.(Grow)
	return f32(v), ok
}

@(private)
definite_size :: proc(s: Size, parent: f32, parent_known: bool) -> (f32, bool) {
	switch v in s {
	case Px:
		return f32(v), true
	case Pct:
		if parent_known {
			return f32(v) * 0.01 * parent, true
		}
	case Grow:
	case Fit:
	}
	return 0, false
}

@(private)
derive_aspect :: proc(other, aspect: f32, target: Axis) -> f32 {
	if aspect <= 0 {
		return other
	}
	return other * aspect if target == .X else other / aspect
}

@(private)
item_align :: proc(item, parent: ^Props) -> Align {
	a := item.align_self
	if a == .Auto {
		a = parent.align
	}
	if a == .Auto {
		a = .Stretch
	}
	return a
}

@(private)
will_stretch :: proc(item, parent: ^Props, a: Axis) -> bool {
	s := axis_size(item, a)
	if size_is_stretch(s) {
		return true
	}
	if size_is_fit(s) {
		return false
	}
	if _, ok := s.(Px); ok {
		return false
	}
	if _, ok := s.(Pct); ok {
		return false
	}
	return item_align(item, parent) == .Stretch
}
