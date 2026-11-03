package tests

import "core:fmt"
import "core:testing"
import ui "../loom"

Clicker :: struct {
	count: int,
	it:    ui.Interaction,
}

clicker :: proc(c: ^Clicker) {
	ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
	c.it = ui.leaf(
		{key = "go", flags = {.Clickable}, props = {w = ui.Px(100), h = ui.Px(40)}},
	)
	if c.it.clicked {
		c.count += 1
	}
}

clicker_frame :: proc(r: ^Rig, c: ^Clicker) -> (passes: int) {
	in_ := rig_input(r)
	for ui.frame(in_) {
		passes += 1
		clicker(c)
	}
	return
}

@(test)
test_passes_idle_frame_runs_once :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	c: Clicker
	r: Rig
	move(&r, 700, 500)
	first := clicker_frame(&r, &c)
	testing.expect_value(t, first, 2)
	testing.expect_value(t, clicker_frame(&r, &c), 1)
	testing.expect_value(t, clicker_frame(&r, &c), 1)
	testing.expect_value(t, ui.stats().passes, 1)
}

@(test)
test_passes_click_counts_once :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	c: Clicker
	r: Rig
	move(&r, 10, 10)
	clicker_frame(&r, &c)
	press(&r)
	clicker_frame(&r, &c)
	release(&r)
	passes := clicker_frame(&r, &c)

	testing.expect_value(t, c.count, 1)
	testing.expect(t, passes >= 2, "a frame with input edges runs again")
	testing.expect(t, !c.it.clicked, "the repeated pass sees no click")
}

@(test)
test_passes_new_node_is_hovered_on_its_first_frame :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	c: Clicker
	r: Rig
	move(&r, 10, 10)
	clicker_frame(&r, &c)

	testing.expect(t, c.it.hovered, "the node is hovered in the emitted pass")
	testing.expect(t, .Hover in c.it.node.state, "and wears .Hover")
}

@(test)
test_passes_radio_loser_clears_the_same_frame :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	value := Tab.Songs
	r: Rig
	p: Pair
	move(&r, 5, 24)
	for ui.frame(rig_input(&r)) {
		p = radio_pair(&value)
	}
	press(&r)
	for ui.frame(rig_input(&r)) {
		p = radio_pair(&value)
	}
	release(&r)
	in_ := rig_input(&r)
	for ui.frame(in_) {
		p = radio_pair(&value)
	}

	testing.expect_value(t, value, Tab.Albums)
	testing.expect(t, .Checked in p.b.node.state, "the winner is checked")
	testing.expect(t, .Checked not_in p.a.node.state, "the loser clears in the same frame")
}

@(test)
test_passes_stop_at_the_cap :: proc(t: ^testing.T) {
	for cap in ([]u32{0, 1, 2}) {
		ctx: ui.Context
		wired(&ctx, {max_passes = cap})

		serial := 0
		passes := 0
		for ui.frame(ui.Input{dt = DT, viewport = VIEWPORT, dpi = 1}) {
			passes += 1
			serial += 1
			ui.leaf({key = fmt.tprintf("n%v", serial)})
		}
		want := cap == 0 ? ui.DEFAULT_MAX_PASSES : int(cap)
		testing.expect_value(t, passes, want)
		testing.expect_value(t, ui.stats().passes, want)
		ui.destroy(&ctx)
	}
}

@(test)
test_passes_set_focus_lands_the_same_frame :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 700, 500)
	it: ui.Interaction
	for ui.frame(rig_input(&r)) {
		it = ui.button("Go", {key = "go"})
	}
	testing.expect(t, !it.focused, "nothing is focused yet")

	for ui.frame(rig_input(&r)) {
		it = ui.button("Go", {key = "go"})
		if !it.focused {
			ui.set_focus(it.id)
		}
	}
	testing.expect(t, it.focused, "set_focus shows in the emitted pass")
}

@(test)
test_passes_slider_drag_reaches_an_earlier_reader :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	value := f32(0)
	seen := f32(-1)
	r: Rig
	move(&r, slider_x(0.25), 10)
	for ui.frame(rig_input(&r)) {
		one_slider(&value)
	}
	press(&r)
	for ui.frame(rig_input(&r)) {
		one_slider(&value)
	}
	testing.expect(t, near(value, 0.25), "press maps x to the value")

	move(&r, slider_x(0.75), 10)
	passes := 0
	for ui.frame(rig_input(&r)) {
		passes += 1
		seen = value
		one_slider(&value)
	}
	testing.expect(t, near(value, 0.75), "the drag moves the value")
	testing.expect_value(t, seen, value)
	testing.expect_value(t, passes, 2)
}

@(test)
test_passes_time_advances_once :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	c: Clicker
	r: Rig
	move(&r, 10, 10)
	clicker_frame(&r, &c)
	press(&r)
	before := ctx.time
	passes := clicker_frame(&r, &c)
	testing.expect(t, passes >= 2, "the press runs a second pass")
	testing.expect_value(t, ctx.time - before, f64(DT))
}

@(test)
test_passes_tab_moves_the_focus_once_the_same_frame :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 700, 500)
	a, b: ui.Interaction
	for ui.frame(rig_input(&r)) {
		a = ui.button("A", {key = "a"})
		b = ui.button("B", {key = "b"})
	}

	key_down(&r, .Tab)
	for ui.frame(rig_input(&r)) {
		a = ui.button("A", {key = "a"})
		b = ui.button("B", {key = "b"})
	}
	testing.expect(t, a.focused, "Tab focuses the first button in the emitted pass")
	testing.expect(t, !b.focused, "and moves it only once")

	key_up(&r, .Tab)
	for ui.frame(rig_input(&r)) {
		a = ui.button("A", {key = "a"})
		b = ui.button("B", {key = "b"})
	}
	testing.expect(t, a.focused, "the focus stays put once Tab is up")
}
