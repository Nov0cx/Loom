package loom

BTN_PAD :: Edges{12, 7, 12, 7}
BTN_RADIUS :: f32(6)
BTN_DUR :: f32(0.12)

CHECK_SIZE :: f32(16)
CHECK_RADIUS :: f32(4)
CHECK_MARK :: f32(52)
CHECK_GAP :: f32(8)
CHECK_DUR :: f32(0.1)

RADIO_RADIUS :: f32(999)

SLIDER_H :: f32(20)
TRACK_H :: f32(4)
TRACK_RADIUS :: f32(2)
THUMB_SIZE :: f32(14)
SLIDER_STEP :: f32(0.01)
SLIDER_PAGE :: f32(0.1)
SLIDER_FINE :: f32(0.1)

merge_element :: proc(dst: ^Element, over: Element, loc := #caller_location) {
	if over.key != "" {
		dst.key = over.key
	}
	dst.flags += over.flags
	if over.text != "" {
		dst.text = over.text
	}
	if over.texture != 0 {
		dst.texture = over.texture
	}
	if over.uv != (Rect{}) {
		dst.uv = over.uv
	}
	if over.tint != (Color{}) {
		dst.tint = over.tint
	}

	src := over
	merge(&dst.props, src.props)
	merge(&dst.hover, src.hover)
	merge(&dst.active, src.active)
	merge(&dst.focus, src.focus)
	merge(&dst.disabled, src.disabled)
	merge(&dst.group_hover, src.group_hover)

	if len(over.rules) > 0 {
		if len(dst.rules) == 0 {
			dst.rules = over.rules
		} else {
			ctx := ctx_of(loc)
			out := make([]Rule, len(dst.rules) + len(over.rules), ctx.frame_allocator)
			copy(out[:len(dst.rules)], dst.rules)
			copy(out[len(dst.rules):], over.rules)
			dst.rules = out
		}
	}

	if over.transition != (Transition{}) {
		dst.transition = over.transition
	}
	dst.state += over.state
}

label :: proc(text: string, el: Element = {}, loc := #caller_location) -> Interaction {
	e := Element {
		text  = text,
		props = {w = FIT, h = FIT},
	}
	merge_element(&e, el, loc)
	return leaf(e, loc)
}

spacer :: proc(size: Size = Grow(1), el: Element = {}, loc := #caller_location) -> Interaction {
	e := Element {
		props = {w = size, h = size},
	}
	merge_element(&e, el, loc)
	return leaf(e, loc)
}

divider :: proc(el: Element = {}, loc := #caller_location) -> Interaction {
	t := theme()
	e := Element {
		props = {w = STRETCH, h = Px(1), align_self = .Stretch, bg = t.divider},
	}
	if p := current(); p != nil {
		d := p.el.props.dir
		if d == .Row || d == .Row_Reverse {
			e.props.w, e.props.h = Px(1), STRETCH
		}
	}
	merge_element(&e, el, loc)
	return leaf(e, loc)
}

button :: proc(text: string, el: Element = {}, loc := #caller_location) -> Interaction {
	t := theme()
	e := Element {
		text = text,
		flags = {.Clickable, .Focusable},
		props = {
			w = FIT,
			h = FIT,
			justify = .Center,
			align = .Center,
			pad = BTN_PAD,
			bg = t.accent,
			color = t.accent_text,
			radius = rad(BTN_RADIUS),
			border = {width = all(1), color = t.accent},
			cursor = .Pointer,
		},
		hover = {bg = t.accent_hover, border = {color = t.accent_hover}},
		active = {bg = fade(t.accent_hover, 0.8)},
		focus = {border = {color = t.text}},
		disabled = {bg = t.raised, color = t.text_faint, cursor = .Not_Allowed},
		transition = {props = {.Bg, .Border_Color}, dur = BTN_DUR, ease = .Out_Quad},
	}
	merge_element(&e, el, loc)
	return leaf(e, loc)
}

image :: proc(tex: Texture, el: Element = {}, loc := #caller_location) -> Interaction {
	e := Element {
		texture = tex,
		props   = {w = Grow(1), h = Grow(1)},
	}
	merge_element(&e, el, loc)
	return leaf(e, loc)
}

@(private)
Slider_State :: struct {
	dragging: bool,
}

@(private)
rule_one :: proc(ctx: ^Context, on: State_Set, props: Props) -> []Rule {
	out := make([]Rule, 1, ctx.frame_allocator)
	out[0] = Rule{on = on, props = props}
	return out
}

@(private)
toggle_row :: proc(ctx: ^Context, gap: f32) -> Element {
	return Element {
		flags = {.Clickable, .Focusable, .Group},
		props = {
			w = FIT,
			h = FIT,
			dir = .Row,
			align = .Center,
			gap = {gap, 0},
			cursor = .Pointer,
		},
		disabled = {cursor = .Not_Allowed, color = ctx.theme.text_faint},
	}
}

@(private)
toggle_box :: proc(ctx: ^Context, on: bool, radius: Radius) -> Element {
	t := &ctx.theme
	return Element {
		key = "box",
		props = {
			w = Px(CHECK_SIZE),
			h = Px(CHECK_SIZE),
			align_self = .Center,
			justify = .Center,
			align = .Center,
			bg = t.surface,
			radius = radius,
			border = {width = all(1), color = t.border},
		},
		group_hover = {border = {color = t.accent}},
		rules = rule_one(ctx, {.Checked}, {bg = t.accent, border = {color = t.accent}}),
		transition = {props = {.Bg, .Border_Color}, dur = CHECK_DUR},
		state = on ? {.Checked} : {},
	}
}

@(private)
toggle_mark :: proc(ctx: ^Context, on: bool, radius: Radius) -> Element {
	return Element {
		key = "mark",
		props = {
			w = Pct(CHECK_MARK),
			h = Pct(CHECK_MARK),
			align_self = .Center,
			radius = radius,
			bg = ctx.theme.accent_text,
			opacity = on ? 1 : 0,
		},
		transition = {props = {.Opacity}, dur = CHECK_DUR},
	}
}

@(private)
toggle_enabled :: proc(e: Element, it: Interaction) -> bool {
	return .Disabled not_in e.flags && .Disabled not_in it.state
}

checkbox :: proc(
	text: string,
	value: ^bool,
	el: Element = {},
	box: Element = {},
	loc := #caller_location,
) -> Interaction {
	ctx := ctx_of(loc)
	row := toggle_row(ctx, CHECK_GAP)
	merge_element(&row, el, loc)

	it := begin(row, loc)
	if it.clicked && toggle_enabled(row, it) {
		value^ = !value^
		it.changed = true
	}
	on := value^
	if on {
		it.node.state += {.Checked}
	}
	it.state = it.node.state

	b := toggle_box(ctx, on, rad(CHECK_RADIUS))
	merge_element(&b, box, loc)
	begin(b, loc)
	leaf(toggle_mark(ctx, on, rad(2)), loc)
	end()

	if text != "" {
		leaf({key = "lbl", text = text, props = {w = FIT, h = FIT}}, loc)
	}
	end()
	return it
}

radio :: proc(
	text: string,
	value: ^$T,
	option: T,
	el: Element = {},
	dot: Element = {},
	loc := #caller_location,
) -> Interaction {
	ctx := ctx_of(loc)
	row := toggle_row(ctx, CHECK_GAP)
	merge_element(&row, el, loc)

	it := begin(row, loc)
	on := value^ == option
	if it.clicked && !on && toggle_enabled(row, it) {
		value^ = option
		on = true
		it.changed = true
	}
	if on {
		it.node.state += {.Checked}
	}
	it.state = it.node.state

	b := toggle_box(ctx, on, rad(RADIO_RADIUS))
	merge_element(&b, dot, loc)
	begin(b, loc)
	leaf(toggle_mark(ctx, on, rad(RADIO_RADIUS)), loc)
	end()

	if text != "" {
		leaf({key = "lbl", text = text, props = {w = FIT, h = FIT}}, loc)
	}
	end()
	return it
}

slider :: proc(
	value: ^f32,
	min_v: f32 = 0,
	max_v: f32 = 1,
	el: Element = {},
	thumb: Element = {},
	loc := #caller_location,
) -> Interaction {
	ctx := ctx_of(loc)
	t := &ctx.theme

	track := Element {
		flags = {.Focusable, .Group},
		props = {
			w = Grow(1),
			h = Px(SLIDER_H),
			dir = .Row,
			align = .Center,
			cursor = .Pointer,
		},
		disabled = {cursor = .Not_Allowed},
	}
	merge_element(&track, el, loc)

	it := begin(track, loc)
	st := state(Slider_State)

	span := max_v - min_v
	entry := clamp(value^, min(min_v, max_v), max(min_v, max_v))
	value^ = entry
	live := toggle_enabled(track, it)

	if live {
		if it.pressed && .Left in ctx.input.mouse_pressed {
			st.dragging = true
			capture_mouse(it.id)
		}
		if st.dragging {
			if .Left not_in ctx.input.mouse_down {
				st.dragging = false
				capture_mouse(0)
			}
			e := inner_edges(&it.node.computed)
			inner_x := it.node.rect.x + e.l
			inner_w := max(it.node.rect.w - e.l - e.r, 0)
			travel := max(inner_w - THUMB_SIZE, 1)
			f := clamp((ctx.input.mouse.x - inner_x - THUMB_SIZE * 0.5) / travel, 0, 1)
			value^ = min_v + span * f
		}
		if it.focused {
			step := span * SLIDER_STEP
			page := span * SLIDER_PAGE
			if .Shift in ctx.input.mods {
				step *= SLIDER_FINE
				page *= SLIDER_FINE
			}
			if key_pressed(.Left) {
				value^ -= step
			}
			if key_pressed(.Right) {
				value^ += step
			}
			if key_pressed(.Page_Down) {
				value^ -= page
			}
			if key_pressed(.Page_Up) {
				value^ += page
			}
			if key_pressed(.Home) {
				value^ = min_v
			}
			if key_pressed(.End) {
				value^ = max_v
			}
		}
	}

	value^ = clamp(value^, min(min_v, max_v), max(min_v, max_v))
	it.changed = value^ != entry

	frac := span != 0 ? clamp((value^ - min_v) / span, 0, 1) : 0

	leaf(
		{
			key = "fill",
			props = {
				w = Grow(frac),
				h = Px(TRACK_H),
				align_self = .Center,
				bg = t.accent,
				radius = rad(TRACK_RADIUS),
			},
		},
		loc,
	)

	th := Element {
		key = "thumb",
		props = {
			w = Px(THUMB_SIZE),
			h = Px(THUMB_SIZE),
			align_self = .Center,
			bg = t.accent_text,
			radius = rad(THUMB_SIZE * 0.5),
			border = {width = all(2), color = t.accent},
		},
		group_hover = {border = {color = t.accent_hover}},
		transition = {props = {.Border_Color}, dur = CHECK_DUR},
	}
	merge_element(&th, thumb, loc)
	leaf(th, loc)

	leaf(
		{
			key = "rest",
			props = {
				w = Grow(1 - frac),
				h = Px(TRACK_H),
				align_self = .Center,
				bg = t.raised,
				radius = rad(TRACK_RADIUS),
			},
		},
		loc,
	)

	end()
	return it
}
