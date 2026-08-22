package tests

import "core:testing"
import "core:unicode/utf8"
import ui "../loom"

CHAR_W :: f32(10)

SCROLLER :: ui.Props {
	w        = ui.Px(200),
	h        = ui.Px(100),
	dir      = .Column,
	overflow = {.Visible, .Scroll},
}

fake_run :: proc(font: ui.Font, size: f32, text: string, spacing: f32, user: rawptr) -> f32 {
	if user != nil {
		(^int)(user)^ += 1
	}
	return (CHAR_W + spacing) * f32(utf8.rune_count_in_string(text))
}

fake_metrics :: proc(font: ui.Font, size: f32, user: rawptr) -> ui.Font_Metrics {
	s := size > 0 ? size : 16
	return {ascent = s * 0.75, descent = s * -0.25, line_gap = 0}
}

fake_backend :: proc() -> ui.Backend {
	b := ui.noop_backend()
	b.measure_run = fake_run
	b.font_metrics = fake_metrics
	return b
}

counting_backend :: proc(counter: ^int) -> ui.Backend {
	b := fake_backend()
	b.user = counter
	return b
}

laid :: proc(ctx: ^ui.Context, root: ui.Props = {}, allocator := context.allocator) {
	ui.init(ctx, ui.Config{backend = fake_backend(), root = root}, allocator)
}

near :: proc(a, b: f32) -> bool {
	d := a - b
	return d < 0.05 && d > -0.05
}

expect_rect :: proc(t: ^testing.T, n: ^ui.Node, x, y, w, h: f32, loc := #caller_location) {
	r := n.rect
	testing.expectf(
		t,
		near(r.x, x) && near(r.y, y) && near(r.w, w) && near(r.h, h),
		"expected rect(%v, %v, %v, %v), got rect(%v, %v, %v, %v)",
		x,
		y,
		w,
		h,
		r.x,
		r.y,
		r.w,
		r.h,
		loc = loc,
	)
}

expect_vec :: proc(t: ^testing.T, v: ui.Vec2, x, y: f32, loc := #caller_location) {
	testing.expectf(
		t,
		near(v.x, x) && near(v.y, y),
		"expected (%v, %v), got (%v, %v)",
		x,
		y,
		v.x,
		v.y,
		loc = loc,
	)
}

@(test)
test_grow_splits_evenly :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "row", props = {w = ui.Px(600), h = ui.Px(50), dir = .Row}})
	a := ui.leaf({key = "a", props = {w = ui.Grow(1), h = ui.STRETCH}}).node
	b := ui.leaf({key = "b", props = {w = ui.Grow(1), h = ui.STRETCH}}).node
	c := ui.leaf({key = "c", props = {w = ui.Grow(1), h = ui.STRETCH}}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, a, 0, 0, 200, 50)
	expect_rect(t, b, 200, 0, 200, 50)
	expect_rect(t, c, 400, 0, 200, 50)
}

@(test)
test_grow_redistributes_past_max :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "row", props = {w = ui.Px(600), h = ui.Px(50), dir = .Row}})
	a := ui.leaf({key = "a", props = {w = ui.Grow(1), max_w = 100}}).node
	b := ui.leaf({key = "b", props = {w = ui.Grow(1)}}).node
	c := ui.leaf({key = "c", props = {w = ui.Grow(1)}}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, a, 0, 0, 100, 50)
	expect_rect(t, b, 100, 0, 250, 50)
	expect_rect(t, c, 350, 0, 250, 50)
}

@(test)
test_grow_weights :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "row", props = {w = ui.Px(400), h = ui.Px(20), dir = .Row}})
	a := ui.leaf({key = "a", props = {w = ui.Grow(1)}}).node
	b := ui.leaf({key = "b", props = {w = ui.Grow(3)}}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, a, 0, 0, 100, 20)
	expect_rect(t, b, 100, 0, 300, 20)
}

@(test)
test_shrink_floors_at_min :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "row", props = {w = ui.Px(300), h = ui.Px(20), dir = .Row}})
	a := ui.leaf({key = "a", props = {w = ui.Px(200), min_w = 150}}).node
	b := ui.leaf({key = "b", props = {w = ui.Px(200)}}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, a, 0, 0, 150, 20)
	expect_rect(t, b, 150, 0, 150, 20)
}

@(test)
test_space_between_pins_last :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin(
		{key = "header", props = {w = ui.Px(600), h = ui.Px(40), dir = .Row, justify = .Space_Between}},
	)
	title := ui.leaf({key = "title", props = {w = ui.Px(100), h = ui.Px(20)}}).node
	ctrl := ui.leaf({key = "ctrl", props = {w = ui.Px(80), h = ui.Px(20)}}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, title, 0, 0, 100, 20)
	expect_rect(t, ctrl, 520, 0, 80, 20)
}

@(test)
test_justify_modes :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "center", props = {w = ui.Px(300), h = ui.Px(20), dir = .Row, justify = .Center}})
	a := ui.leaf({key = "a", props = {w = ui.Px(100), h = ui.Px(20)}}).node
	ui.end()
	ui.begin({key = "evenly", props = {w = ui.Px(300), h = ui.Px(20), dir = .Row, justify = .Space_Evenly}})
	b := ui.leaf({key = "b", props = {w = ui.Px(100), h = ui.Px(20)}}).node
	c := ui.leaf({key = "c", props = {w = ui.Px(100), h = ui.Px(20)}}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, a, 100, 0, 100, 20)
	testing.expect_value(t, b.rect.x, f32(300 + 100.0 / 3.0))
	testing.expect_value(t, c.rect.x, f32(300 + 100.0 / 3.0 * 2 + 100))
}

@(test)
test_align_center_and_end :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "row", props = {w = ui.Px(300), h = ui.Px(100), dir = .Row, align = .Center}})
	a := ui.leaf({key = "a", props = {w = ui.Px(50), h = ui.Px(20)}}).node
	b := ui.leaf({key = "b", props = {w = ui.Px(50), h = ui.Px(20), align_self = .End}}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, a, 0, 40, 50, 20)
	expect_rect(t, b, 50, 80, 50, 20)
}

@(test)
test_default_align_stretches_cross :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "row", props = {w = ui.Px(300), h = ui.Px(100), dir = .Row}})
	a := ui.leaf({key = "a", props = {w = ui.Px(50)}}).node
	b := ui.leaf({key = "b", props = {w = ui.Px(50), h = ui.FIT}}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, a, 0, 0, 50, 100)
	expect_rect(t, b, 50, 0, 50, 0)
}

@(test)
test_padding_and_border_shrink_content_box :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin(
		{
			key = "box",
			props = {
				w = ui.Px(200),
				h = ui.Px(100),
				pad = ui.all(10),
				border = {width = ui.all(2), color = RED},
			},
		},
	)
	a := ui.leaf({key = "a", props = {w = ui.STRETCH, h = ui.STRETCH}}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, a, 12, 12, 176, 76)
}

@(test)
test_margins_do_not_collapse :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "col", props = {w = ui.Px(200), h = ui.Px(200), dir = .Column}})
	a := ui.leaf({key = "a", props = {w = ui.Px(50), h = ui.Px(20), margin = ui.all(10)}}).node
	b := ui.leaf({key = "b", props = {w = ui.Px(50), h = ui.Px(20), margin = ui.all(10)}}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, a, 10, 10, 50, 20)
	expect_rect(t, b, 10, 50, 50, 20)
}

@(test)
test_wrapping_tag_list :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	row := ui.begin(
		{key = "tags", props = {w = ui.Px(300), h = ui.FIT, dir = .Row, wrap = .Wrap, gap = {10, 5}}},
	).node
	a := ui.leaf({key = "a", props = {w = ui.Px(100), h = ui.Px(20)}}).node
	b := ui.leaf({key = "b", props = {w = ui.Px(120), h = ui.Px(20)}}).node
	c := ui.leaf({key = "c", props = {w = ui.Px(90), h = ui.Px(20)}}).node
	d := ui.leaf({key = "d", props = {w = ui.Px(200), h = ui.Px(20)}}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, a, 0, 0, 100, 20)
	expect_rect(t, b, 110, 0, 120, 20)
	expect_rect(t, c, 0, 25, 90, 20)
	expect_rect(t, d, 100, 25, 200, 20)
	testing.expect_value(t, row.rect.h, f32(45))
}

@(test)
test_wrap_reverse_stacks_lines_backwards :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "tags", props = {w = ui.Px(100), h = ui.Px(60), dir = .Row, wrap = .Wrap_Reverse}})
	a := ui.leaf({key = "a", props = {w = ui.Px(60), h = ui.Px(20)}}).node
	b := ui.leaf({key = "b", props = {w = ui.Px(60), h = ui.Px(20)}}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, a, 0, 40, 60, 20)
	expect_rect(t, b, 0, 20, 60, 20)
}

@(test)
test_nested_fit_content_columns :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	outer := ui.begin(
		{
			key = "outer",
			props = {w = ui.FIT, h = ui.FIT, dir = .Column, gap = {0, 5}, pad = ui.all(10)},
		},
	).node
	a := ui.leaf({key = "a", props = {w = ui.Px(50), h = ui.Px(20)}}).node
	b := ui.leaf({key = "b", props = {w = ui.Px(80), h = ui.Px(30)}}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, outer, 0, 0, 100, 75)
	expect_rect(t, a, 10, 10, 50, 20)
	expect_rect(t, b, 10, 35, 80, 30)
}

@(test)
test_text_drives_fit_content :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx, ui.Props{font_size = 16})
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "col", props = {w = ui.FIT, h = ui.FIT, dir = .Column}})
	label := ui.leaf({key = "label", text = "Songs"}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, label, 0, 0, 50, 16)
}

@(test)
test_text_wraps_inside_constrained_width :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx, ui.Props{font_size = 16})
	defer ui.destroy(&ctx)

	open_frame()
	col := ui.begin({key = "col", props = {w = ui.Px(100), h = ui.FIT, dir = .Column}}).node
	label := ui.leaf({key = "label", text = "aaa bbb ccc ddd"}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, label, 0, 0, 100, 32)
	testing.expect_value(t, col.rect.h, f32(32))
}

@(test)
test_absolute_child_uses_positioned_ancestor :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	panel := ui.begin(
		{
			key = "panel",
			props = {w = ui.Px(400), h = ui.Px(300), position = .Absolute, inset = {l = 50, t = 40}},
		},
	).node
	pop := ui.leaf(
		{
			key = "pop",
			props = {h = ui.Px(60), position = .Absolute, inset = {l = 10, t = 10, r = 10}},
		},
	).node
	pinned := ui.leaf(
		{key = "pinned", props = {w = ui.Px(50), h = ui.Px(30), position = .Absolute, inset = {b = 20}}},
	).node
	static := ui.leaf(
		{key = "static", props = {w = ui.Px(20), h = ui.Px(20), position = .Absolute}},
	).node
	ui.end()
	ui.end_frame()

	expect_rect(t, panel, 50, 40, 400, 300)
	expect_rect(t, pop, 60, 50, 380, 60)
	expect_rect(t, pinned, 50, 290, 50, 30)
	expect_rect(t, static, 50, 40, 20, 20)
}

@(test)
test_fixed_child_uses_viewport :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "panel", props = {w = ui.Px(200), h = ui.Px(200), margin = ui.all(30)}})
	fixed := ui.leaf(
		{key = "fixed", props = {w = ui.Px(40), h = ui.Px(40), position = .Fixed, inset = {r = 10, b = 10}}},
	).node
	ui.end()
	ui.end_frame()

	expect_rect(t, fixed, VIEWPORT.x - 50, VIEWPORT.y - 50, 40, 40)
}

@(test)
test_out_of_flow_leaves_flow_untouched :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	row := ui.begin({key = "row", props = {w = ui.FIT, h = ui.Px(40), dir = .Row}}).node
	a := ui.leaf({key = "a", props = {w = ui.Px(50), h = ui.Px(20)}}).node
	ui.leaf({key = "float", props = {w = ui.Px(500), h = ui.Px(500), position = .Absolute}})
	b := ui.leaf({key = "b", props = {w = ui.Px(50), h = ui.Px(20)}}).node
	ui.end()
	ui.end_frame()

	testing.expect_value(t, row.rect.w, f32(100))
	expect_rect(t, a, 0, 0, 50, 20)
	expect_rect(t, b, 50, 0, 50, 20)
}

@(test)
test_scroll_offset_shifts_children_and_clamps :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	list := ui.begin({key = "list", props = SCROLLER}).node
	for key in ([]string{"r0", "r1", "r2"}) {
		ui.leaf({key = key, props = {w = ui.STRETCH, h = ui.Px(100)}})
	}
	ui.end()
	ui.end_frame()

	expect_vec(t, list.content, 200, 300)
	testing.expect_value(t, list.scroll.y, f32(0))

	list.scroll.y = 500

	open_frame()
	ui.begin({key = "list", props = SCROLLER})
	for key in ([]string{"r0", "r1", "r2"}) {
		ui.leaf({key = key, props = {w = ui.STRETCH, h = ui.Px(100)}})
	}
	ui.end()
	ui.end_frame()

	testing.expect_value(t, list.scroll.y, f32(200))

	open_frame()
	ui.begin({key = "list", props = SCROLLER})
	row := ui.leaf({key = "r0", props = {w = ui.STRETCH, h = ui.Px(100)}}).node
	ui.end()
	ui.end_frame()

	testing.expect_value(t, list.scroll.y, f32(0))
	expect_rect(t, row, 0, -200, 200, 100)
}

@(test)
test_order_is_a_stable_sort :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "row", props = {w = ui.Px(600), h = ui.Px(20), dir = .Row}})
	a := ui.leaf({key = "a", props = {w = ui.Px(100), h = ui.Px(20), order = 2}}).node
	b := ui.leaf({key = "b", props = {w = ui.Px(100), h = ui.Px(20), order = 1}}).node
	c := ui.leaf({key = "c", props = {w = ui.Px(100), h = ui.Px(20), order = 1}}).node
	ui.end()
	ui.end_frame()

	testing.expect_value(t, b.rect.x, f32(0))
	testing.expect_value(t, c.rect.x, f32(100))
	testing.expect_value(t, a.rect.x, f32(200))
}

@(test)
test_row_reverse_composes_with_order :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "row", props = {w = ui.Px(600), h = ui.Px(20), dir = .Row_Reverse}})
	a := ui.leaf({key = "a", props = {w = ui.Px(100), h = ui.Px(20), order = 2}}).node
	b := ui.leaf({key = "b", props = {w = ui.Px(100), h = ui.Px(20), order = 1}}).node
	c := ui.leaf({key = "c", props = {w = ui.Px(100), h = ui.Px(20), order = 1}}).node
	ui.end()
	ui.end_frame()

	testing.expect_value(t, b.rect.x, f32(500))
	testing.expect_value(t, c.rect.x, f32(400))
	testing.expect_value(t, a.rect.x, f32(300))
}

@(test)
test_aspect_derives_the_free_axis :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "row", props = {w = ui.Px(600), h = ui.Px(200), dir = .Row, align = .Start}})
	a := ui.leaf({key = "a", props = {w = ui.Px(120), aspect = 2}}).node
	b := ui.leaf({key = "b", props = {h = ui.Px(50), aspect = 0.5}}).node
	c := ui.leaf({key = "c", props = {w = ui.Grow(1), aspect = 4}}).node
	ui.end()
	ui.end_frame()

	testing.expect_value(t, a.rect.h, f32(60))
	testing.expect_value(t, b.rect.w, f32(25))
	testing.expect_value(t, c.rect.w, f32(455))
	testing.expect_value(t, c.rect.h, f32(455.0 / 4.0))
}

@(test)
test_pct_resolves_against_parent_content_box :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "box", props = {w = ui.Px(400), h = ui.Px(200), pad = ui.all(20)}})
	a := ui.leaf({key = "a", props = {w = ui.Pct(50), h = ui.Pct(50)}}).node
	ui.end()
	ui.end_frame()

	expect_rect(t, a, 20, 20, 180, 80)
}

@(test)
test_pct_in_auto_parent_falls_back_to_fit :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	col := ui.begin({key = "col", props = {w = ui.Px(200), h = ui.FIT, dir = .Column}}).node
	a := ui.begin({key = "a", props = {h = ui.Pct(50)}}).node
	ui.leaf({key = "inner", props = {w = ui.Px(10), h = ui.Px(30)}})
	ui.end()
	ui.end()
	ui.end_frame()

	testing.expect_value(t, a.rect.h, f32(30))
	testing.expect_value(t, col.rect.h, f32(30))
}

@(test)
test_baseline_alignment :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	row := ui.begin({key = "row", props = {w = ui.Px(400), h = ui.FIT, dir = .Row, align = .Baseline}}).node
	big := ui.leaf({key = "big", text = "A", props = {font_size = 20}}).node
	small := ui.leaf({key = "small", text = "b", props = {font_size = 10}}).node
	ui.end()
	ui.end_frame()

	testing.expect_value(t, big.rect.y, f32(0))
	testing.expect_value(t, small.rect.y, f32(7.5))
	testing.expect_value(t, row.rect.h, f32(20))
}

@(test)
test_demo_shell_layout :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx, ui.Props{font_size = 14})
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "root", props = {w = ui.Grow(1), h = ui.Grow(1), dir = .Row}})

	sidebar := ui.begin(
		{
			key = "sidebar",
			props = {w = ui.Px(220), h = ui.STRETCH, dir = .Column, pad = ui.all(12)},
		},
	).node
	nav := ui.leaf({key = "nav", text = "Songs", props = {w = ui.STRETCH, pad = ui.xy(8, 6)}}).node
	ui.end()

	library := ui.begin(
		{key = "library", props = {w = ui.Grow(1), h = ui.STRETCH, dir = .Column}},
	).node
	header := ui.begin(
		{
			key = "header",
			props = {
				w = ui.STRETCH,
				dir = .Row,
				align = .Center,
				gap = {12, 0},
				pad = ui.xy(20, 16),
				border = {width = {b = 1}, color = GREY},
			},
		},
	).node
	title := ui.leaf({key = "title", text = "Songs", props = {font_size = 22, w = ui.Grow(1)}}).node
	slider := ui.leaf({key = "slider", props = {w = ui.Px(120), h = ui.Px(16)}}).node
	ui.end()
	rows := ui.begin({key = "rows", props = {w = ui.STRETCH, h = ui.Grow(1), dir = .Column}}).node
	ui.end()
	ui.end()

	ui.end()
	ui.end_frame()

	expect_rect(t, sidebar, 0, 0, 220, VIEWPORT.y)
	expect_rect(t, nav, 12, 12, 196, 14 + 12)
	expect_rect(t, library, 220, 0, VIEWPORT.x - 220, VIEWPORT.y)
	expect_rect(t, header, 220, 0, 580, 22 + 32 + 1)
	expect_rect(t, title, 240, 16, 580 - 40 - 12 - 120, 22)
	expect_rect(t, slider, 800 - 20 - 120, 19, 120, 16)
	expect_rect(t, rows, 220, 55, 580, VIEWPORT.y - 55)
}
