package tests

import "core:testing"
import ui "../loom"

V_COUNT :: 1000
V_ROW :: f32(20)
V_VIEW :: f32(200)

virtual_frame :: proc(built: ^int) -> (it: ui.Interaction, first, last: int) {
	it = ui.scroll({key = "list", props = {w = ui.Px(200), h = ui.Px(V_VIEW)}})
	defer ui.end()

	first, last = ui.virtual(V_COUNT, V_ROW, {key = "rows"})
	for i in first ..< last {
		ui.push_id_int(i64(i))
		ui.leaf({key = "row", props = {h = ui.Px(V_ROW)}})
		ui.pop_id()
		built^ += 1
	}
	ui.end_virtual()
	return
}

@(test)
test_a_virtual_list_builds_only_the_visible_rows :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	built := 0
	it: ui.Interaction
	first, last := 0, 0
	for _ in 0 ..< 2 {
		rig_open(&r)
		it, first, last = virtual_frame(&built)
		ui.end_frame()
	}

	// 200 px of viewport is ten rows, plus one partial and the overscan.
	testing.expect_value(t, first, 0)
	testing.expect_value(t, last, 13)
	testing.expect(t, last < V_COUNT / 10, "a thousand rows do not become a thousand nodes")
	// The list still measures its whole length, so the scrollbar is honest.
	testing.expect_value(t, it.node.content.y, f32(V_COUNT) * V_ROW)
	testing.expect(t, ui.scroll_max(it.node).y > 0, "there is somewhere to scroll to")
}

@(test)
test_the_virtual_window_follows_the_scroll :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	built := 0
	it: ui.Interaction
	first, last := 0, 0

	move(&r, 100, 100)
	for _ in 0 ..< 2 {
		rig_open(&r)
		it, first, last = virtual_frame(&built)
		ui.end_frame()
	}
	testing.expect_value(t, first, 0)

	for _ in 0 ..< 40 {
		spin(&r, 0, 3)
		rig_open(&r)
		it, first, last = virtual_frame(&built)
		ui.end_frame()
	}

	testing.expect(t, it.node.scroll.y > 0, "the wheel moved the list")
	testing.expect(t, first > 0, "the window follows the offset")
	testing.expect(t, last > first, "the window is not empty")
	testing.expect(t, last - first <= 20, "the window stays small")
}

@(test)
test_an_empty_virtual_list_builds_nothing :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	rig_open(&r)
	ui.scroll({key = "list", props = {w = ui.Px(200), h = ui.Px(V_VIEW)}})
	first, last := ui.virtual(0, V_ROW, {key = "rows"})
	ui.end_virtual()
	ui.end()
	ui.end_frame()

	testing.expect_value(t, first, 0)
	testing.expect_value(t, last, 0)
}
