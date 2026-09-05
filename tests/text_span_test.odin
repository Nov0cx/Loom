package tests

import "core:testing"
import ui "../loom"

TAB_W :: f32(40)

// The fake backend is ten pixels a rune, so every width below is exact.
tabbed :: proc(text: string, origin: f32 = 0) -> f32 {
	return ui.measure(
		text,
		ui.Props{font_size = 16, text_wrap = .None, tab_size = TAB_W, tab_origin = origin},
	).x
}

@(test)
test_a_tab_advances_to_the_next_stop :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	rig_open(&Rig{})
	testing.expect_value(t, tabbed("ab\tc"), f32(50))
	testing.expect_value(t, tabbed("\t"), TAB_W)
	// A pen already on a stop still moves a whole cell.
	testing.expect_value(t, tabbed("abcd\te"), f32(90))
	ui.end_frame()
}

@(test)
test_the_tab_origin_moves_the_pen_not_the_grid :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	rig_open(&Rig{})
	// "ab" ends the pen at 20, so the tab goes to 40 and "x" to 50.
	testing.expect_value(t, tabbed("ab\tx"), f32(50))
	// The same text measured as if it began at pen 30 ends at 90, width 60.
	testing.expect_value(t, tabbed("ab\tx", 30), f32(60))
	ui.end_frame()
}

@(test)
test_a_span_cuts_the_line_into_coloured_runs :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	spans := []ui.Text_Span{{start = 0, end = 2, color = RED}, {start = 3, end = 4, color = BLUE}}
	it: ui.Interaction
	for _ in 0 ..< 2 {
		rig_open(&Rig{})
		it = ui.leaf(
			{
				key = "row",
				text = "abcd",
				spans = spans,
				props = {font_size = 16, text_wrap = .None, w = ui.Px(200), h = ui.Px(20)},
			},
		)
		ui.end_frame()
	}

	runs := ui.text_runs(it.node)
	testing.expect_value(t, len(runs), 3)
	c0, ok0 := runs[0].color.?
	_, ok1 := runs[1].color.?
	c2, ok2 := runs[2].color.?
	testing.expect_value(t, runs[0].text, "ab")
	testing.expect(t, ok0 && c0 == RED, "the first run keeps its span colour")
	testing.expect_value(t, runs[1].text, "c")
	testing.expect(t, !ok1, "the gap between spans takes the node colour")
	testing.expect_value(t, runs[2].text, "d")
	testing.expect(t, ok2 && c2 == BLUE, "the last run keeps its span colour")
	testing.expect_value(t, runs[1].pos.x - runs[0].pos.x, f32(20))
}

@(test)
test_a_tab_cuts_the_line_and_places_the_next_run :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	it: ui.Interaction
	for _ in 0 ..< 2 {
		rig_open(&Rig{})
		it = ui.leaf(
			{
				key = "row",
				text = "ab\tc",
				props = {
					font_size = 16,
					text_wrap = .None,
					tab_size = TAB_W,
					w = ui.Px(200),
					h = ui.Px(20),
				},
			},
		)
		ui.end_frame()
	}

	runs := ui.text_runs(it.node)
	testing.expect_value(t, len(runs), 2)
	testing.expect_value(t, runs[0].text, "ab")
	testing.expect_value(t, runs[1].text, "c")
	testing.expect_value(t, runs[1].pos.x - runs[0].pos.x, TAB_W)
}

// ---- the positional text contract -------------------------------------------

@(test)
test_caret_x_and_offset_at_fall_back_to_measurement :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	rig_open(&Rig{})
	p := ui.Props{font_size = 16, text_wrap = .None}
	testing.expect_value(t, ui.caret_x("abcd", 0, p), f32(0))
	testing.expect_value(t, ui.caret_x("abcd", 3, p), f32(30))
	testing.expect_value(t, ui.offset_at("abcd", 0, p), 0)
	testing.expect_value(t, ui.offset_at("abcd", 29, p), 3)
	ui.end_frame()
}

Pos_Probe :: struct {
	offset_calls: int,
	index_calls:  int,
}

@(test)
test_the_backend_answers_a_positional_query_when_it_can :: proc(t: ^testing.T) {
	probe: Pos_Probe
	b := fake_backend()
	b.user = &probe
	b.offset_x =
	proc(
		font: ui.Font,
		size: f32,
		text: string,
		spacing, tab_origin: f32,
		at: int,
		user: rawptr,
	) -> f32 {
		(^Pos_Probe)(user).offset_calls += 1
		return 123
	}
	b.index_at =
	proc(
		font: ui.Font,
		size: f32,
		text: string,
		spacing, tab_origin, x: f32,
		user: rawptr,
	) -> int {
		(^Pos_Probe)(user).index_calls += 1
		return 2
	}

	ctx: ui.Context
	ui.init(&ctx, ui.Config{backend = b})
	defer ui.destroy(&ctx)

	rig_open(&Rig{})
	p := ui.Props{font_size = 16, text_wrap = .None}
	testing.expect_value(t, ui.caret_x("abcd", 3, p), f32(123))
	testing.expect_value(t, ui.offset_at("abcd", 15, p), 2)
	ui.end_frame()

	testing.expect_value(t, probe.offset_calls, 1)
	testing.expect_value(t, probe.index_calls, 1)
}

PAINT_GREEN :: ui.Color{40, 200, 90, 255}

// ---- the painter -------------------------------------------------------------

@(test)
test_painted_shapes_land_in_the_node_slot :: proc(t: ^testing.T) {
	ctx: ui.Context
	// The root padding moves the row, so a wrong translation shows up.
	wired(&ctx, ui.Config{root = ui.Props{pad = ui.all(10)}})
	defer ui.destroy(&ctx)

	list: ui.Draw_List
	for _ in 0 ..< 2 {
		rig_open(&Rig{})
		ui.begin(
			{
				key = "row",
				text = "ab",
				props = {w = ui.Px(100), h = ui.Px(20), font_size = 16, text_wrap = .None},
			},
		)
		ui.paint_rect({2, 3, 4, 5}, RED)
		ui.paint_line({0, 10}, {8, 10}, 1, BLUE)
		ui.paint_poly({{0, 0}, {4, 0}, {2, 4}}, PAINT_GREEN)
		ui.end()
		list = ui.end_frame()
	}

	kinds := make([dynamic]string, 0, 8, context.temp_allocator)
	defer delete(kinds)
	rect: ui.Cmd_Rect
	line: ui.Cmd_Line
	poly: ui.Cmd_Poly
	for cmd in list.cmds {
		switch v in cmd {
		case ui.Cmd_Rect:
			append(&kinds, "rect")
			rect = v
		case ui.Cmd_Text:
			append(&kinds, "text")
		case ui.Cmd_Line:
			append(&kinds, "line")
			line = v
		case ui.Cmd_Poly:
			append(&kinds, "poly")
			poly = v
		case ui.Cmd_Image, ui.Cmd_Push_Clip, ui.Cmd_Pop_Clip, ui.Cmd_Custom:
		}
	}

	testing.expect_value(t, len(kinds), 4)
	testing.expect_value(t, kinds[0], "rect")
	testing.expect_value(t, kinds[1], "text")
	testing.expect_value(t, kinds[2], "line")
	testing.expect_value(t, kinds[3], "poly")

	// Every coordinate is local to the node, which sits at the root padding.
	testing.expect_value(t, rect.rect, ui.Rect{12, 13, 4, 5})
	testing.expect_value(t, line.a, ui.Vec2{10, 20})
	testing.expect_value(t, line.b, ui.Vec2{18, 20})
	testing.expect_value(t, len(poly.points), 3)
	testing.expect_value(t, poly.points[2], ui.Vec2{12, 14})
	testing.expect_value(t, poly.color, PAINT_GREEN)
}

@(test)
test_a_transparent_shape_is_not_emitted :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	rig_open(&Rig{})
	ui.begin({key = "row", props = {w = ui.Px(100), h = ui.Px(20)}})
	ui.paint_rect({0, 0, 4, 4}, ui.Color{255, 0, 0, 0})
	ui.paint_line({0, 0}, {4, 0}, 0, RED)
	ui.paint_poly({{0, 0}, {4, 0}}, RED)
	ui.end()
	list := ui.end_frame()

	for cmd in list.cmds {
		switch _ in cmd {
		case ui.Cmd_Rect, ui.Cmd_Line, ui.Cmd_Poly:
			testing.fail_now(t, "a zero-alpha, zero-width or degenerate shape draws nothing")
		case ui.Cmd_Text, ui.Cmd_Image, ui.Cmd_Push_Clip, ui.Cmd_Pop_Clip, ui.Cmd_Custom:
		}
	}
}
