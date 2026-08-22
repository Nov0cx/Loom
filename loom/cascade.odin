package loom

import "core:mem"

@(private)
prop_ptr :: proc(p: ^Props, prop: Prop) -> rawptr {
	return rawptr(uintptr(p) + PROP_TABLE[prop].offset)
}

@(private)
prop_copy :: proc(dst, src: ^Props, prop: Prop) {
	mem.copy(prop_ptr(dst, prop), prop_ptr(src, prop), PROP_TABLE[prop].size)
}

@(private)
prop_zero :: proc(dst: ^Props, prop: Prop) {
	mem.zero(prop_ptr(dst, prop), PROP_TABLE[prop].size)
}

@(private)
paint_set :: proc(p: Paint) -> bool {
	switch _ in p {
	case Color:
		return true
	case Gradient:
		return true
	}
	return false
}

@(private)
prop_is_set :: proc(p: ^Props, prop: Prop) -> bool {
	q := prop_ptr(p, prop)
	switch PROP_TABLE[prop].kind {
	case .F32:
		return (^f32)(q)^ != 0
	case .Vec2:
		return (^Vec2)(q)^ != Vec2{}
	case .Edges:
		return (^Edges)(q)^ != Edges{}
	case .Radius:
		return (^Radius)(q)^ != Radius{}
	case .Color:
		return (^Color)(q)^ != Color{}
	case .Shadow:
		return (^Shadow)(q)^ != Shadow{}
	case .Size:
		return (^Size)(q)^ != nil
	case .Paint:
		return paint_set((^Paint)(q)^)
	case .Color_Opt:
		_, ok := (^Maybe(Color))(q)^.(Color)
		return ok
	case .F32_Opt:
		_, ok := (^Maybe(f32))(q)^.(f32)
		return ok
	}
	return false
}

@(private)
mode_ptr :: proc(p: ^Props, m: Mode_Prop) -> rawptr {
	return rawptr(uintptr(p) + MODE_TABLE[m].offset)
}

@(private)
mode_is_set :: proc(p: ^Props, m: Mode_Prop) -> bool {
	info := MODE_TABLE[m]
	bytes := ([^]u8)(mode_ptr(p, m))[:info.size]
	for b in bytes {
		if b != 0 {
			return true
		}
	}
	return false
}

@(private)
mode_copy :: proc(dst, src: ^Props, m: Mode_Prop) {
	mem.copy(mode_ptr(dst, m), mode_ptr(src, m), MODE_TABLE[m].size)
}

merge :: proc(dst: ^Props, variant: Props) {
	src := variant
	for p in src.clear {
		prop_zero(dst, p)
	}
	for p in Prop {
		if prop_is_set(&src, p) {
			prop_copy(dst, &src, p)
		}
	}
	for m in Mode_Prop {
		if mode_is_set(&src, m) {
			mode_copy(dst, &src, m)
		}
	}
}

@(private)
inherit_props :: proc(dst, parent: ^Props) {
	for p in INHERITED_PROPS {
		if !prop_is_set(dst, p) {
			prop_copy(dst, parent, p)
		}
	}
	for m in INHERITED_MODES {
		if !mode_is_set(dst, m) {
			mode_copy(dst, parent, m)
		}
	}
}

@(private)
resolve_states :: proc(n: ^Node, disabled, group_hover: bool) -> bool {
	n.state -= CARRIED_STATES

	if disabled || .Disabled in n.flags || .Disabled in n.el.state {
		n.state += {.Disabled}
	}
	if group_hover || .Group_Hover in n.el.state {
		n.state += {.Group_Hover}
	}

	child_group := group_hover
	if .Group in n.flags {
		child_group = .Hover in n.state
	}

	found := .Focus in n.state
	for c := n.first_child; c != nil; c = c.next {
		if resolve_states(c, .Disabled in n.state, child_group) {
			found = true
		}
	}
	if found && .Focus not_in n.state {
		n.state += {.Focus_Within}
	}
	return found
}

@(private)
cascade_node :: proc(ctx: ^Context, n: ^Node, parent: ^Props) {
	target := n.el.props

	if .Group_Hover in n.state {
		merge(&target, n.el.group_hover)
	}
	if .Hover in n.state {
		merge(&target, n.el.hover)
	}
	if .Focus in n.state {
		merge(&target, n.el.focus)
	}
	if .Active in n.state {
		merge(&target, n.el.active)
	}
	if .Disabled in n.state {
		merge(&target, n.el.disabled)
	}
	for r in n.el.rules {
		if r.on <= n.state {
			merge(&target, r.props)
		}
	}

	if parent != nil {
		inherit_props(&target, parent)
	}
	target.clear = {}

	animate_node(ctx, n, target)

	for c := n.first_child; c != nil; c = c.next {
		cascade_node(ctx, c, &n.computed)
	}
}

@(private)
cascade :: proc(ctx: ^Context) {
	if ctx.root == nil {
		return
	}
	resolve_states(ctx.root, false, false)
	ctx.animating = false
	cascade_node(ctx, ctx.root, nil)
}
