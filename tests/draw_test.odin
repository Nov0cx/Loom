package tests

import "core:fmt"
import "core:mem"
import "core:testing"
import ui "../loom"

cmd_counts :: proc(list: ui.Draw_List) -> (rects, texts, images, pushes, pops, customs: int) {
	for c in list.cmds {
		switch _ in c {
		case ui.Cmd_Rect:
			rects += 1
		case ui.Cmd_Text:
			texts += 1
		case ui.Cmd_Image:
			images += 1
		case ui.Cmd_Push_Clip:
			pushes += 1
		case ui.Cmd_Pop_Clip:
			pops += 1
		case ui.Cmd_Custom:
			customs += 1
		case ui.Cmd_Line, ui.Cmd_Poly:
		}
	}
	return
}

clip_balanced :: proc(list: ui.Draw_List) -> bool {
	depth := 0
	for c in list.cmds {
		#partial switch _ in c {
		case ui.Cmd_Push_Clip:
			depth += 1
		case ui.Cmd_Pop_Clip:
			depth -= 1
			if depth < 0 {
				return false
			}
		}
	}
	return depth == 0
}

rect_index :: proc(list: ui.Draw_List, color: ui.Color) -> int {
	for c, i in list.cmds {
		r, ok := c.(ui.Cmd_Rect)
		if !ok {
			continue
		}
		if p, is_color := r.paint.(ui.Color); is_color && p == color {
			return i
		}
	}
	return -1
}

@(test)
test_draw_golden_small_tree :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx, {font_size = 16, color = ui.hex(0xE4E4EB)})
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin(
		{
			key = "sidebar",
			props = {
				w = ui.Px(220),
				h = ui.STRETCH,
				dir = .Column,
				bg = ui.hex(0x1C1C21),
				pad = ui.all(12),
				radius = ui.rad(6),
				border = {width = ui.all(1), color = ui.hex(0x2E2E36)},
				overflow = {.Hidden, .Hidden},
			},
		},
	)
	ui.leaf({key = "title", text = "Library"})
	ui.leaf({key = "songs", props = {h = ui.Px(32), w = ui.STRETCH, bg = ui.hex(0x6366F1)}})
	ui.end()
	list := ui.end_frame()

	got := ui.dump_list_string(list, context.temp_allocator)
	expected := `rect(0,0,220,600) bg=#1C1C21FF r=(6,6,6,6) border=(1,1,1,1)/#2E2E36FF
push_clip(1,1,218,598) r=(5,5,5,5)
  text(13,25) "Library" f=0 s=16 #E4E4EBFF
  rect(13,29,194,32) bg=#6366F1FF
pop_clip
`
	testing.expect_value(t, got, expected)
}

@(test)
test_draw_stable_across_frames :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx, {font_size = 16, color = ui.hex(0xE4E4EB)})
	defer ui.destroy(&ctx)

	build :: proc() -> string {
		open_frame()
		ui.begin({key = "panel", props = {w = ui.Px(100), h = ui.Px(60), bg = ui.hex(0x202024)}})
		ui.leaf({key = "label", text = "hi"})
		ui.end()
		return ui.dump_list_string(ui.end_frame(), context.temp_allocator)
	}

	build()
	a := build()
	b := build()
	testing.expect_value(t, a, b)
	testing.expect(t, len(a) > 0, "expected a non-empty command stream")
}

@(test)
test_clip_push_pop_balanced :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "a", flags = {.Clip}, props = {w = ui.Px(300), h = ui.Px(300)}})
	ui.begin({key = "b", props = {w = ui.Px(200), h = ui.Px(200), overflow = {.Hidden, .Hidden}}})
	ui.begin({key = "c", props = {w = ui.Px(100), h = ui.Px(100), overflow = {.Visible, .Scroll}}})
	ui.leaf({key = "d", props = {w = ui.Px(50), h = ui.Px(50), bg = ui.hex(0xFF0000)}})
	ui.end()
	ui.end()
	ui.end()
	list := ui.end_frame()

	_, _, _, pushes, pops, _ := cmd_counts(list)
	testing.expect(t, clip_balanced(list), "clip stack must be balanced")
	testing.expect_value(t, pushes, 3)
	testing.expect_value(t, pops, 3)
}

@(test)
test_clip_only_when_clipping :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	count :: proc(flags: ui.Flags, ov: [2]ui.Overflow) -> int {
		open_frame()
		ui.begin(
			{key = "box", flags = flags, props = {w = ui.Px(80), h = ui.Px(80), overflow = ov}},
		)
		ui.leaf({key = "kid", props = {w = ui.Px(20), h = ui.Px(20), bg = ui.hex(0x00FF00)}})
		ui.end()
		_, _, _, pushes, _, _ := cmd_counts(ui.end_frame())
		return pushes
	}

	testing.expect_value(t, count({}, {.Visible, .Visible}), 0)
	testing.expect_value(t, count({.Clip}, {.Visible, .Visible}), 1)
	testing.expect_value(t, count({.Scroll_Y}, {.Visible, .Visible}), 1)
	testing.expect_value(t, count({}, {.Visible, .Hidden}), 1)
}

ROWS :: 10000

@(test)
test_offscreen_rows_bounded :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	build :: proc() -> ui.Id {
		open_frame()
		id := ui.begin(
			{
				key = "list",
				props = {
					w = ui.Px(300),
					h = ui.Px(300),
					dir = .Column,
					overflow = {.Visible, .Scroll},
				},
			},
		).id
		for i in 0 ..< ROWS {
			ui.leaf(
				{
					key = fmt.tprintf("row%d", i),
					props = {w = ui.STRETCH, h = ui.Px(20), bg = ui.hex(0x303038)},
				},
			)
		}
		ui.end()
		return id
	}

	id := build()
	ui.end_frame()

	n := ui.find(id)
	testing.expect(t, n != nil, "scroller must exist")
	n.scroll = {0, 100_000}

	build()
	list := ui.end_frame()

	testing.expectf(
		t,
		len(list.cmds) <= 64,
		"expected a bounded command count, got %v for %v rows",
		len(list.cmds),
		ROWS,
	)
	testing.expectf(t, len(list.cmds) >= 8, "expected visible rows to emit, got %v", len(list.cmds))
	testing.expect(t, clip_balanced(list), "clip stack must be balanced")
}

@(test)
test_floating_paints_after_main_tree :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin(
		{
			key = "panel",
			flags = {.Clip},
			props = {w = ui.Px(200), h = ui.Px(200), bg = ui.hex(0x111111)},
		},
	)
	ui.leaf(
		{
			key = "menu",
			flags = {.Floating},
			props = {
				position = .Fixed,
				inset = ui.ltrb(400, 400, 0, 0),
				w = ui.Px(120),
				h = ui.Px(80),
				bg = ui.hex(0xFF00FF),
			},
		},
	)
	ui.end()
	ui.leaf({key = "other", props = {w = ui.Px(100), h = ui.Px(100), bg = ui.hex(0x00FF00)}})
	list := ui.end_frame()

	menu := rect_index(list, ui.hex(0xFF00FF))
	other := rect_index(list, ui.hex(0x00FF00))
	testing.expect(t, menu >= 0 && other >= 0, "both rects must be emitted")
	testing.expectf(t, menu > other, "floating layer must paint last, got %v vs %v", menu, other)

	pop := -1
	for c, i in list.cmds {
		if _, ok := c.(ui.Cmd_Pop_Clip); ok {
			pop = i
		}
	}
	testing.expectf(t, pop < menu, "floating node must escape the panel clip, pop at %v", pop)
	testing.expect(t, clip_balanced(list), "clip stack must be balanced")
}

@(test)
test_opacity_folds_into_subtree :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx, {font_size = 16, color = ui.hex(0xFFFFFF)})
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "group", flags = {.No_Anim}, props = {opacity = 0.5}})
	ui.leaf(
		{
			key = "card",
			flags = {.No_Anim},
			props = {
				w = ui.Px(100),
				h = ui.Px(40),
				bg = ui.rgba(255, 0, 0, 255),
				border = {width = ui.all(2), color = ui.rgba(0, 255, 0, 255)},
				shadow = {blur = 4, color = ui.rgba(0, 0, 255, 255)},
			},
		},
	)
	ui.begin({key = "inner", flags = {.No_Anim}, props = {opacity = 0.5}})
	ui.leaf(
		{
			key = "deep",
			flags = {.No_Anim},
			props = {w = ui.Px(10), h = ui.Px(10), bg = ui.rgba(255, 255, 0, 255)},
		},
	)
	ui.end()
	ui.end()
	list := ui.end_frame()

	found_card, found_deep := false, false
	for c in list.cmds {
		r, ok := c.(ui.Cmd_Rect)
		if !ok {
			continue
		}
		col, is_color := r.paint.(ui.Color)
		if !is_color {
			continue
		}
		if col[0] == 255 && col[1] == 0 && col[2] == 0 {
			found_card = true
			testing.expect_value(t, col[3], u8(128))
			testing.expect_value(t, r.border.color[3], u8(128))
			testing.expect_value(t, r.shadow.color[3], u8(128))
		}
		if col[0] == 255 && col[1] == 255 && col[2] == 0 {
			found_deep = true
			testing.expect_value(t, col[3], u8(64))
		}
	}
	testing.expect(t, found_card, "the half-opacity card must be emitted")
	testing.expect(t, found_deep, "the quarter-opacity grandchild must be emitted")
}

@(test)
test_opacity_zero_skips_subtree :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "hidden", flags = {.No_Anim}, props = {opacity = 0}})
	ui.leaf({key = "a", props = {w = ui.Px(10), h = ui.Px(10), bg = ui.hex(0xFF0000)}})
	ui.leaf({key = "b", props = {w = ui.Px(10), h = ui.Px(10), bg = ui.hex(0x00FF00)}})
	ui.end()
	ui.leaf({key = "shown", props = {w = ui.Px(10), h = ui.Px(10), bg = ui.hex(0x0000FF)}})
	list := ui.end_frame()

	testing.expect_value(t, rect_index(list, ui.hex(0xFF0000)), -1)
	testing.expect_value(t, rect_index(list, ui.hex(0x00FF00)), -1)
	testing.expect(t, rect_index(list, ui.hex(0x0000FF)) >= 0, "the sibling must still paint")
}

@(test)
test_gradient_stops_survive_end_frame :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	stops := [2]ui.Stop{{t = 0, color = ui.rgba(255, 0, 0, 255)}, {t = 1, color = ui.rgba(0, 0, 255, 255)}}

	open_frame()
	ui.leaf(
		{
			key = "grad",
			props = {
				w = ui.Px(100),
				h = ui.Px(50),
				bg = ui.Gradient{kind = .Linear, angle = 45, stops = stops[:]},
			},
		},
	)
	list := ui.end_frame()

	stops[0].color = ui.rgba(1, 2, 3, 4)
	stops[1].color = ui.rgba(5, 6, 7, 8)

	found := false
	for c in list.cmds {
		r, ok := c.(ui.Cmd_Rect)
		if !ok {
			continue
		}
		g, is_grad := r.paint.(ui.Gradient)
		if !is_grad {
			continue
		}
		found = true
		testing.expect_value(t, len(g.stops), 2)
		testing.expect_value(t, g.stops[0].color, ui.rgba(255, 0, 0, 255))
		testing.expect_value(t, g.stops[1].color, ui.rgba(0, 0, 255, 255))
	}
	testing.expect(t, found, "the gradient rect must be emitted")
}

@(test)
test_text_emitted_at_baseline :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx, {font_size = 16, color = ui.hex(0xFFFFFF)})
	defer ui.destroy(&ctx)

	open_frame()
	n := ui.leaf({key = "label", text = "hi"}).node
	list := ui.end_frame()

	runs := ui.text_runs(n)
	testing.expect_value(t, len(runs), 1)

	found := false
	for c in list.cmds {
		txt, ok := c.(ui.Cmd_Text)
		if !ok {
			continue
		}
		found = true
		testing.expect_value(t, txt.text, "hi")
		testing.expect_value(t, txt.pos, runs[0].pos)
		testing.expect_value(t, txt.pos.y, f32(12))
		testing.expect_value(t, txt.size, f32(16))
	}
	testing.expect(t, found, "the label must emit a text command")
}

@(test)
test_custom_emits_in_paint_order :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	drawn: int
	cb :: proc(node: ^ui.Node, user: rawptr) {
		(^int)(user)^ += 1
	}

	open_frame()
	ui.leaf({key = "before", props = {w = ui.Px(10), h = ui.Px(10), bg = ui.hex(0xFF0000)}})
	ui.custom({key = "chart", props = {w = ui.Px(10), h = ui.Px(10)}}, cb, &drawn)
	ui.leaf({key = "after", props = {w = ui.Px(10), h = ui.Px(10), bg = ui.hex(0x00FF00)}})
	list := ui.end_frame()

	before := rect_index(list, ui.hex(0xFF0000))
	after := rect_index(list, ui.hex(0x00FF00))
	custom := -1
	for c, i in list.cmds {
		if v, ok := c.(ui.Cmd_Custom); ok {
			custom = i
			v.draw(v.node, v.user)
		}
	}

	testing.expect(t, custom > before && custom < after, "custom must sit between its siblings")
	testing.expect_value(t, drawn, 1)
}

@(test)
test_image_uses_content_box :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.leaf(
		{
			key = "icon",
			texture = ui.Texture(7),
			props = {w = ui.Px(64), h = ui.Px(64), pad = ui.all(4), border = {width = ui.all(2), color = ui.hex(0xFFFFFF)}},
		},
	)
	list := ui.end_frame()

	found := false
	for c in list.cmds {
		img, ok := c.(ui.Cmd_Image)
		if !ok {
			continue
		}
		found = true
		testing.expect_value(t, img.tex, ui.Texture(7))
		testing.expect_value(t, img.tint, ui.rgba(255, 255, 255, 255))
		testing.expect_value(t, img.rect, ui.Rect{6, 6, 52, 52})
	}
	testing.expect(t, found, "the textured node must emit an image command")
}

@(test)
test_z_orders_within_parent :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.leaf({key = "top", props = {w = ui.Px(10), h = ui.Px(10), z = 1, bg = ui.hex(0xFF0000)}})
	ui.leaf({key = "bottom", props = {w = ui.Px(10), h = ui.Px(10), z = -1, bg = ui.hex(0x00FF00)}})
	ui.leaf({key = "mid", props = {w = ui.Px(10), h = ui.Px(10), bg = ui.hex(0x0000FF)}})
	list := ui.end_frame()

	top := rect_index(list, ui.hex(0xFF0000))
	bottom := rect_index(list, ui.hex(0x00FF00))
	mid := rect_index(list, ui.hex(0x0000FF))
	testing.expect(t, bottom < mid && mid < top, "siblings must paint in z order")
}

@(test)
test_z_is_scoped_to_the_parent :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "a", props = {w = ui.Px(50), h = ui.Px(50)}})
	ui.leaf({key = "high", props = {w = ui.Px(10), h = ui.Px(10), z = 100, bg = ui.hex(0xFF0000)}})
	ui.end()
	ui.leaf({key = "b", props = {w = ui.Px(50), h = ui.Px(50), bg = ui.hex(0x00FF00)}})
	list := ui.end_frame()

	high := rect_index(list, ui.hex(0xFF0000))
	b := rect_index(list, ui.hex(0x00FF00))
	testing.expect(t, high < b, "a high z inside a panel must not punch through a later panel")
}

@(test)
test_debug_overlay_does_not_perturb :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx, {font_size = 16, color = ui.hex(0xFFFFFF)})
	defer ui.destroy(&ctx)

	build :: proc() -> ui.Draw_List {
		open_frame()
		ui.begin({key = "panel", props = {w = ui.Px(120), h = ui.Px(60), bg = ui.hex(0x202024)}})
		ui.leaf({key = "label", text = "hello"})
		ui.end()
		return ui.end_frame()
	}

	build()
	plain := build()
	plain_cmds := len(plain.cmds)
	tree := ui.dump_tree_string(context.temp_allocator)
	before := ui.stats()

	ui.debug_overlay(true)
	ui.debug_rects(true)
	over := build()
	after := ui.stats()

	testing.expect_value(t, ui.dump_tree_string(context.temp_allocator), tree)
	testing.expect_value(t, after.text_measures, before.text_measures)
	testing.expect_value(t, after.commands, plain_cmds)
	testing.expect(t, len(over.cmds) > plain_cmds, "the overlay must append commands")
	testing.expect(t, clip_balanced(over), "the overlay must not unbalance the clip stack")

	ui.debug_overlay(false)
	ui.debug_rects(false)
	again := build()
	testing.expect_value(t, len(again.cmds), plain_cmds)
}

@(test)
test_empty_container_emits_nothing :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "wrap", props = {w = ui.Px(100), h = ui.Px(100)}})
	ui.leaf({key = "inner", props = {w = ui.Px(10), h = ui.Px(10)}})
	ui.end()
	list := ui.end_frame()

	testing.expect_value(t, len(list.cmds), 0)
}

@(test)
test_emission_uses_only_the_frame_arena :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	{
		ctx: ui.Context
		ui.init(
			&ctx,
			ui.Config{backend = fake_backend(), root = {font_size = 16}},
			mem.tracking_allocator(&track),
		)
		defer ui.destroy(&ctx)

		build :: proc() {
			open_frame()
			ui.begin(
				{
					key = "panel",
					flags = {.Clip},
					props = {w = ui.Px(200), h = ui.Px(120), bg = ui.hex(0x202024)},
				},
			)
			ui.leaf({key = "label", text = "hello"})
			ui.leaf({key = "chip", props = {w = ui.Px(40), h = ui.Px(20), bg = ui.hex(0x6366F1)}})
			ui.end()
			ui.end_frame()
		}

		for _ in 0 ..< 4 {
			build()
		}
		before := track.total_memory_allocated

		for _ in 0 ..< 8 {
			build()
		}
		testing.expectf(
			t,
			track.total_memory_allocated == before,
			"emission allocated %v permanent bytes across 8 steady-state frames",
			track.total_memory_allocated - before,
		)
	}
}
