package tests

import "core:reflect"
import "core:testing"
import ui "../loom"

RED :: ui.Color{220, 40, 40, 255}
GREEN :: ui.Color{40, 200, 90, 255}
BLUE :: ui.Color{60, 90, 240, 255}
GREY :: ui.Color{120, 120, 130, 255}
WHITE :: ui.Color{240, 240, 245, 255}

styled :: proc(ctx: ^ui.Context, root: ui.Props = {}, allocator := context.allocator) {
	ui.init(ctx, ui.Config{backend = ui.noop_backend(), root = root}, allocator)
}

frame_dt :: proc(dt: f32) {
	ui.begin_frame(ui.Input{dt = dt, viewport = VIEWPORT, dpi = 1, mouse = {-1, -1}})
}

one :: proc(el: ui.Element) -> ui.Props {
	open_frame()
	n := ui.leaf(el).node
	ui.end_frame()
	return n.computed
}

bg_color :: proc(t: ^testing.T, p: ui.Props, loc := #caller_location) -> ui.Color {
	c, ok := p.bg.(ui.Color)
	testing.expectf(t, ok, "bg is not a Color", loc = loc)
	return c
}

@(test)
test_base_props_land_in_computed :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	p := one({key = "a", props = {dir = .Column, bg = RED, pad = ui.all(8)}})
	testing.expect_value(t, p.dir, ui.Direction.Column)
	testing.expect_value(t, bg_color(t, p), RED)
	testing.expect_value(t, p.pad, ui.all(8))
}

@(test)
test_partial_variant_leaves_other_fields :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	p := one({key = "a", state = {.Hover}, props = {bg = RED, pad = ui.all(8)}, hover = {bg = BLUE}})
	testing.expect_value(t, bg_color(t, p), BLUE)
	testing.expect_value(t, p.pad, ui.all(8))
}

@(test)
test_variant_cascade_order :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	el := ui.Element {
		key         = "btn",
		props       = {bg = GREY},
		group_hover = {bg = ui.Color{1, 0, 0, 255}},
		hover       = {bg = ui.Color{2, 0, 0, 255}},
		focus       = {bg = ui.Color{3, 0, 0, 255}},
		active      = {bg = ui.Color{4, 0, 0, 255}},
		disabled    = {bg = ui.Color{5, 0, 0, 255}},
	}

	el.state = {.Group_Hover}
	testing.expect_value(t, bg_color(t, one(el)), ui.Color{1, 0, 0, 255})

	el.state = {.Group_Hover, .Hover}
	testing.expect_value(t, bg_color(t, one(el)), ui.Color{2, 0, 0, 255})

	el.state = {.Hover, .Focus}
	testing.expect_value(t, bg_color(t, one(el)), ui.Color{3, 0, 0, 255})

	el.state = {.Hover, .Focus, .Active}
	testing.expect_value(t, bg_color(t, one(el)), ui.Color{4, 0, 0, 255})

	el.state = {.Hover, .Focus, .Active, .Disabled}
	testing.expect_value(t, bg_color(t, one(el)), ui.Color{5, 0, 0, 255})
}

@(test)
test_rules_run_last_and_in_slice_order :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	rules := []ui.Rule{{on = {.Hover}, props = {bg = GREEN}}, {on = {.Hover}, props = {bg = BLUE}}}
	p := one({key = "a", state = {.Hover}, props = {bg = RED}, hover = {bg = GREY}, rules = rules})
	testing.expect_value(t, bg_color(t, p), BLUE)
}

@(test)
test_rule_requires_a_subset :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	rules := []ui.Rule{{on = {.Hover, .Focus}, props = {bg = BLUE}}}
	p := one({key = "a", state = {.Hover}, props = {bg = RED}, rules = rules})
	testing.expect_value(t, bg_color(t, p), RED)

	always := []ui.Rule{{props = {bg = GREEN}}}
	q := one({key = "b", props = {bg = RED}, rules = always})
	testing.expect_value(t, bg_color(t, q), GREEN)
}

@(test)
test_clear_resets_a_prop :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	shadow := ui.Shadow {
		offset = {0, 8},
		blur   = 24,
		color  = ui.rgba(0, 0, 0, 120),
	}

	kept := one({key = "a", state = {.Hover}, props = {shadow = shadow}, hover = {bg = BLUE}})
	testing.expect_value(t, kept.shadow, shadow)

	gone := one({key = "b", state = {.Hover}, props = {shadow = shadow}, hover = {clear = {.Shadow}}})
	testing.expect_value(t, gone.shadow, ui.Shadow{})
}

@(test)
test_clear_applies_before_variant_fields :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	p := one({key = "a", state = {.Hover}, props = {bg = GREY}, hover = {clear = {.Bg}, bg = RED}})
	testing.expect_value(t, bg_color(t, p), RED)
}

@(test)
test_all_props_clears_props_but_not_modes :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	p := one(
		{
			key = "a",
			state = {.Hover},
			props = {dir = .Column, bg = RED, pad = ui.all(8), radius = ui.rad(6)},
			hover = {clear = ui.ALL_PROPS},
		},
	)
	testing.expect(t, p.bg == nil, "bg should be cleared")
	testing.expect_value(t, p.pad, ui.Edges{})
	testing.expect_value(t, p.radius, ui.Radius{})
	testing.expect_value(t, p.dir, ui.Direction.Column)
}

@(test)
test_border_width_and_color_are_independent :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	base := ui.Border {
		width = {b = 1},
		color = GREY,
	}

	p := one({key = "a", state = {.Hover}, props = {border = base}, hover = {border = {color = RED}}})
	testing.expect_value(t, p.border.width, ui.Edges{b = 1})
	testing.expect_value(t, p.border.color, RED)

	q := one(
		{key = "b", state = {.Hover}, props = {border = base}, hover = {clear = {.Border_Color}}},
	)
	testing.expect_value(t, q.border.width, ui.Edges{b = 1})
	testing.expect_value(t, q.border.color, ui.Color{})
}

@(test)
test_maybe_unset_is_not_zero :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	kept := one({key = "a", state = {.Hover}, props = {opacity = 0}, hover = {bg = BLUE}})
	v, ok := kept.opacity.?
	testing.expect(t, ok, "opacity should stay set")
	testing.expect_value(t, v, 0)

	over := one({key = "b", state = {.Hover}, props = {opacity = 1}, hover = {opacity = 0}})
	w, ok2 := over.opacity.?
	testing.expect(t, ok2, "opacity should stay set")
	testing.expect_value(t, w, 0)
}

@(test)
test_inheritance_three_levels :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(
		&ctx,
		ui.Props{font_size = 14, color = WHITE, cursor = .Pointer, font = ui.Font(3), line_height = 1.4},
	)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "a"})
	ui.begin({key = "b"})
	deep := ui.leaf({key = "c"}).node
	ui.end()
	ui.end()
	ui.end_frame()

	testing.expect_value(t, deep.computed.font_size, 14)
	testing.expect_value(t, deep.computed.line_height, 1.4)
	testing.expect_value(t, deep.computed.cursor, ui.Cursor.Pointer)
	testing.expect_value(t, deep.computed.font, ui.Font(3))
	c, ok := deep.computed.color.?
	testing.expect(t, ok, "color should inherit")
	testing.expect_value(t, c, WHITE)
}

@(test)
test_a_middle_level_overrides_for_its_subtree :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx, ui.Props{font_size = 14})
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "a"})
	ui.begin({key = "b", props = {font_size = 20}})
	inner := ui.leaf({key = "c"}).node
	ui.end()
	sibling := ui.leaf({key = "d"}).node
	ui.end()
	ui.end_frame()

	testing.expect_value(t, inner.computed.font_size, 20)
	testing.expect_value(t, sibling.computed.font_size, 14)
}

@(test)
test_non_inherited_props_do_not_inherit :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "a", props = {pad = ui.all(10), bg = RED}})
	child := ui.leaf({key = "b"}).node
	ui.end()
	ui.end_frame()

	testing.expect_value(t, child.computed.pad, ui.Edges{})
	testing.expect(t, child.computed.bg == nil, "bg must not inherit")
}

@(test)
test_group_hover_from_a_forced_ancestor_hover :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	build :: proc(hovered: bool) -> ^ui.Node {
		open_frame()
		ui.begin({key = "row", flags = {.Group}, state = hovered ? {.Hover} : {}})
		icon := ui.leaf({key = "icon", props = {opacity = 0}, group_hover = {opacity = 1}}).node
		ui.end()
		ui.end_frame()
		return icon
	}

	on := build(true)
	v, ok := on.computed.opacity.?
	testing.expect(t, ok, "opacity should be set")
	testing.expect_value(t, v, 1)
	testing.expect(t, .Group_Hover in on.state, "icon should carry .Group_Hover")

	off := build(false)
	w, ok2 := off.computed.opacity.?
	testing.expect(t, ok2, "opacity should be set")
	testing.expect_value(t, w, 0)
}

@(test)
test_nearest_group_wins :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "outer", flags = {.Group}, state = {.Hover}})
	direct := ui.leaf({key = "direct"}).node
	ui.begin({key = "inner", flags = {.Group}})
	nested := ui.leaf({key = "nested"}).node
	ui.end()
	ui.end()
	ui.end_frame()

	testing.expect(t, .Group_Hover in direct.state, "direct child of the hovered group")
	testing.expect(t, .Group_Hover not_in nested.state, "inner group is not hovered")
}

@(test)
test_disabled_cascades_to_the_subtree :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "panel", flags = {.Disabled}})
	ui.begin({key = "row"})
	deep := ui.leaf({key = "btn", props = {bg = RED}, disabled = {bg = GREY}}).node
	ui.end()
	ui.end()
	ui.end_frame()

	testing.expect(t, .Disabled in deep.state, "disabled must reach the whole subtree")
	testing.expect_value(t, bg_color(t, deep.computed), GREY)
}

@(test)
test_focus_within_marks_ancestors_only :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	rules := []ui.Rule{{on = {.Focus_Within}, props = {bg = BLUE}}}

	open_frame()
	outer := ui.begin({key = "outer", props = {bg = RED}, rules = rules}).node
	inner := ui.begin({key = "inner"}).node
	field := ui.leaf({key = "field", state = {.Focus}}).node
	ui.end()
	sibling := ui.leaf({key = "sibling"}).node
	ui.end()
	ui.end_frame()

	testing.expect(t, .Focus_Within in outer.state, "outer is an ancestor of the focused node")
	testing.expect(t, .Focus_Within in inner.state, "inner is an ancestor of the focused node")
	testing.expect(t, .Focus_Within not_in field.state, "the focused node itself has .Focus")
	testing.expect(t, .Focus_Within not_in sibling.state, "siblings are untouched")
	testing.expect_value(t, bg_color(t, outer.computed), BLUE)
}

@(test)
test_carried_states_report_last_frame :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	build :: proc() -> ui.State_Set {
		open_frame()
		ui.begin({key = "row", flags = {.Group}, state = {.Hover}})
		seen := ui.leaf({key = "icon"}).state
		ui.end()
		ui.end_frame()
		return seen
	}

	first := build()
	testing.expect(t, .Group_Hover not_in first, "nothing to carry on the first frame")

	second := build()
	testing.expect(t, .Group_Hover in second, "Interaction reports last frame's group hover")
}

@(test)
test_first_frame_snaps :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	p := one(
		{
			key = "a",
			state = {.Hover},
			props = {bg = RED},
			hover = {bg = BLUE},
			transition = {props = {.Bg}, dur = 0.5},
		},
	)
	testing.expect_value(t, bg_color(t, p), BLUE)
}

@(test)
test_no_anim_snaps :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	el := ui.Element {
		key        = "a",
		flags      = {.No_Anim},
		props      = {bg = RED},
		hover      = {bg = BLUE},
		transition = {props = {.Bg}, dur = 0.5},
	}
	one(el)

	el.state = {.Hover}
	testing.expect_value(t, bg_color(t, one(el)), BLUE)
}

@(test)
test_transition_interpolates_over_frames :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	el := ui.Element {
		key        = "a",
		props      = {opacity = 0},
		hover      = {opacity = 1},
		transition = {props = {.Opacity}, dur = 0.1},
	}

	step :: proc(el: ui.Element) -> f32 {
		frame_dt(1.0 / 60.0)
		n := ui.leaf(el).node
		ui.end_frame()
		v, _ := n.computed.opacity.?
		return v
	}

	testing.expect_value(t, step(el), 0)

	el.state = {.Hover}
	prev := f32(0)
	for _ in 0 ..< 3 {
		v := step(el)
		testing.expect(t, v > prev, "opacity must rise")
		testing.expect(t, v < 1, "opacity must not reach the target yet")
		prev = v
	}
	for _ in 0 ..< 6 {
		step(el)
	}
	testing.expect_value(t, step(el), 1)
	testing.expect(t, !ui.animating(), "the clock should have finished")
}

@(test)
test_transition_reversed_midflight_is_continuous :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	DT :: f32(1.0 / 60.0)
	DUR :: f32(0.2)

	el := ui.Element {
		key        = "a",
		props      = {opacity = 0},
		hover      = {opacity = 1},
		transition = {props = {.Opacity}, dur = DUR},
	}

	step :: proc(el: ui.Element) -> f32 {
		frame_dt(DT)
		n := ui.leaf(el).node
		ui.end_frame()
		v, _ := n.computed.opacity.?
		return v
	}

	step(el)
	el.state = {.Hover}

	prev := f32(0)
	limit := DT / DUR + 0.001
	for _ in 0 ..< 6 {
		v := step(el)
		testing.expect(t, abs(v - prev) <= limit, "no jump on the way in")
		prev = v
	}

	testing.expect(t, prev > 0 && prev < 1, "must still be mid-flight")

	el.state = {}
	for _ in 0 ..< 20 {
		v := step(el)
		testing.expect(t, abs(v - prev) <= limit, "no jump after reversing")
		prev = v
	}
	testing.expect_value(t, prev, 0)
}

@(test)
test_delay_holds_the_origin :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	el := ui.Element {
		key        = "a",
		props      = {opacity = 0},
		hover      = {opacity = 1},
		transition = {props = {.Opacity}, dur = 0.2, delay = 0.05},
	}

	step :: proc(el: ui.Element) -> f32 {
		frame_dt(1.0 / 60.0)
		n := ui.leaf(el).node
		ui.end_frame()
		v, _ := n.computed.opacity.?
		return v
	}

	step(el)
	el.state = {.Hover}
	for _ in 0 ..< 2 {
		testing.expect_value(t, step(el), 0)
	}
	for _ in 0 ..< 3 {
		step(el)
	}
	testing.expect(t, step(el) > 0, "the clock starts after the delay")
}

@(test)
test_spring_settles_exactly :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	el := ui.Element {
		key        = "a",
		props      = {opacity = 0},
		hover      = {opacity = 1},
		transition = {props = {.Opacity}, ease = .Spring},
	}

	step :: proc(el: ui.Element) -> f32 {
		frame_dt(1.0 / 60.0)
		n := ui.leaf(el).node
		ui.end_frame()
		v, _ := n.computed.opacity.?
		return v
	}

	step(el)
	el.state = {.Hover}
	last := f32(0)
	for _ in 0 ..< 120 {
		last = step(el)
	}
	testing.expect_value(t, last, 1)
	testing.expect(t, !ui.animating(), "the spring should have settled")
}

@(test)
test_size_variant_mismatch_snaps :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	el := ui.Element {
		key        = "a",
		props      = {w = ui.Px(100)},
		hover      = {w = ui.Grow(1)},
		transition = {props = {.W}, dur = 0.5},
	}
	one(el)

	el.state = {.Hover}
	p := one(el)
	g, ok := p.w.(ui.Grow)
	testing.expect(t, ok, "a union variant change must snap")
	testing.expect_value(t, g, ui.Grow(1))
}

@(test)
test_paint_gradient_snaps :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	stops := []ui.Stop{{t = 0, color = RED}, {t = 1, color = BLUE}}
	grad := ui.Gradient {
		stops = stops,
	}

	el := ui.Element {
		key        = "a",
		props      = {bg = RED},
		hover      = {bg = grad},
		transition = {props = {.Bg}, dur = 0.5},
	}
	one(el)

	el.state = {.Hover}
	p := one(el)
	_, ok := p.bg.(ui.Gradient)
	testing.expect(t, ok, "Color to Gradient must snap")
}

@(test)
test_out_back_never_wraps_a_color :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	el := ui.Element {
		key        = "a",
		props      = {bg = ui.Color{0, 0, 0, 255}},
		hover      = {bg = ui.Color{255, 255, 255, 255}},
		transition = {props = {.Bg}, dur = 0.2, ease = .Out_Back},
	}

	step :: proc(el: ui.Element) -> ui.Color {
		frame_dt(1.0 / 60.0)
		n := ui.leaf(el).node
		ui.end_frame()
		c, _ := n.computed.bg.(ui.Color)
		return c
	}

	step(el)
	el.state = {.Hover}
	for _ in 0 ..< 20 {
		c := step(el)
		for i in 0 ..< 3 {
			testing.expect(t, c[i] <= 255, "clamped, never wrapped")
		}
	}
	testing.expect_value(t, step(el), ui.Color{255, 255, 255, 255})
}

@(test)
test_animating_tracks_the_clocks :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	el := ui.Element {
		key        = "a",
		props      = {opacity = 0},
		hover      = {opacity = 1},
		transition = {props = {.Opacity}, dur = 0.1},
	}

	step :: proc(el: ui.Element) {
		frame_dt(1.0 / 60.0)
		ui.leaf(el)
		ui.end_frame()
	}

	step(el)
	testing.expect(t, !ui.animating(), "settled before anything changes")

	el.state = {.Hover}
	step(el)
	testing.expect(t, ui.animating(), "a clock is running")

	for _ in 0 ..< 10 {
		step(el)
	}
	testing.expect(t, !ui.animating(), "settled again")
}

@(test)
test_props_field_count_is_locked :: proc(t: ^testing.T) {
	names := reflect.struct_field_names(ui.Props)
	testing.expect_value(t, len(names), 34)
}

@(test)
test_every_field_merges_from_a_variant :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	full := ui.Props {
		dir            = .Column_Reverse,
		wrap           = .Wrap_Reverse,
		justify        = .Space_Evenly,
		align          = .Baseline,
		gap            = {3, 5},
		pad            = ui.ltrb(1, 2, 3, 4),
		w              = ui.Px(11),
		h              = ui.Pct(22),
		min_w          = 33,
		min_h          = 44,
		max_w          = 55,
		max_h          = 66,
		margin         = ui.ltrb(5, 6, 7, 8),
		align_self     = .Center,
		order          = 9,
		aspect         = 1.5,
		position       = .Absolute,
		inset          = ui.ltrb(9, 10, 11, 12),
		z              = 13,
		overflow       = {.Scroll, .Hidden},
		bg             = RED,
		border         = {width = ui.all(2), color = BLUE},
		radius         = ui.rad4(1, 2, 3, 4),
		shadow         = {offset = {1, 2}, blur = 3, spread = 4, color = GREY, inset = true},
		opacity        = 0.5,
		font           = ui.Font(7),
		font_size      = 17,
		color          = WHITE,
		line_height    = 1.6,
		letter_spacing = 0.5,
		text_align     = .Justify,
		text_wrap      = .Ellipsis,
		cursor         = .Grabbing,
	}

	p := one({key = "a", state = {.Hover}, hover = full})

	testing.expect_value(t, p.dir, full.dir)
	testing.expect_value(t, p.wrap, full.wrap)
	testing.expect_value(t, p.justify, full.justify)
	testing.expect_value(t, p.align, full.align)
	testing.expect_value(t, p.gap, full.gap)
	testing.expect_value(t, p.pad, full.pad)
	testing.expect_value(t, p.w, full.w)
	testing.expect_value(t, p.h, full.h)
	testing.expect_value(t, p.min_w, full.min_w)
	testing.expect_value(t, p.min_h, full.min_h)
	testing.expect_value(t, p.max_w, full.max_w)
	testing.expect_value(t, p.max_h, full.max_h)
	testing.expect_value(t, p.margin, full.margin)
	testing.expect_value(t, p.align_self, full.align_self)
	testing.expect_value(t, p.order, full.order)
	testing.expect_value(t, p.aspect, full.aspect)
	testing.expect_value(t, p.position, full.position)
	testing.expect_value(t, p.inset, full.inset)
	testing.expect_value(t, p.z, full.z)
	testing.expect_value(t, p.overflow, full.overflow)
	testing.expect_value(t, bg_color(t, p), RED)
	testing.expect_value(t, p.border, full.border)
	testing.expect_value(t, p.radius, full.radius)
	testing.expect_value(t, p.shadow, full.shadow)
	testing.expect_value(t, p.opacity, full.opacity)
	testing.expect_value(t, p.font, full.font)
	testing.expect_value(t, p.font_size, full.font_size)
	testing.expect_value(t, p.color, full.color)
	testing.expect_value(t, p.line_height, full.line_height)
	testing.expect_value(t, p.letter_spacing, full.letter_spacing)
	testing.expect_value(t, p.text_align, full.text_align)
	testing.expect_value(t, p.text_wrap, full.text_wrap)
	testing.expect_value(t, p.cursor, full.cursor)
}

button_style :: proc() -> ui.Element {
	return ui.Element {
		flags = {.Clickable, .Focusable},
		props = {
			pad = {12, 8, 12, 8},
			bg = ui.Color{40, 40, 47, 255},
			radius = {6, 6, 6, 6},
			cursor = .Pointer,
		},
		hover = {bg = ui.Color{56, 56, 66, 255}},
		active = {bg = ui.Color{72, 72, 84, 255}},
		disabled = {opacity = 0.4, cursor = .Not_Allowed},
		transition = {props = {.Bg, .Color, .Opacity, .Radius}, dur = 0.12, ease = .Out_Quad},
	}
}

@(test)
test_the_idea_button_resolves_per_state :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	settle :: proc(el: ui.Element) -> ui.Props {
		n: ^ui.Node
		for _ in 0 ..< 20 {
			frame_dt(1.0 / 60.0)
			n = ui.leaf(el).node
			ui.end_frame()
		}
		return n.computed
	}

	el := button_style()
	el.key = "btn"

	base := settle(el)
	testing.expect_value(t, bg_color(t, base), ui.Color{40, 40, 47, 255})
	testing.expect_value(t, base.pad, ui.Edges{12, 8, 12, 8})
	testing.expect_value(t, base.radius, ui.rad(6))
	testing.expect_value(t, base.cursor, ui.Cursor.Pointer)

	el.state = {.Hover}
	hover := settle(el)
	testing.expect_value(t, bg_color(t, hover), ui.Color{56, 56, 66, 255})
	testing.expect_value(t, hover.pad, ui.Edges{12, 8, 12, 8})

	el.state = {.Hover, .Active}
	active := settle(el)
	testing.expect_value(t, bg_color(t, active), ui.Color{72, 72, 84, 255})

	el.state = {.Disabled}
	off := settle(el)
	testing.expect_value(t, bg_color(t, off), ui.Color{40, 40, 47, 255})
	testing.expect_value(t, off.cursor, ui.Cursor.Not_Allowed)
	v, ok := off.opacity.?
	testing.expect(t, ok, "disabled sets opacity")
	testing.expect_value(t, v, 0.4)
	testing.expect(t, !ui.animating(), "the button should have settled")
}
