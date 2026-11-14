package tests

import "core:testing"
import ui "../loom"

// A modal: `outer` before a scope that holds `in1` and `in2`.
Scoped :: struct {
	outer, in1, in2: ui.Interaction,
}

scoped_form :: proc() -> (out: Scoped) {
	ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
	out.outer = ui.leaf({key = "outer", flags = {.Clickable, .Focusable}, props = {w = ui.Px(100), h = ui.Px(50)}})
	{
		ui.scope({key = "modal", focus_scope = true, props = {w = ui.Px(400), h = ui.Px(100), dir = .Row}})
		out.in1 = ui.leaf({key = "in1", flags = {.Clickable, .Focusable}, props = {w = ui.Px(100), h = ui.Px(50)}})
		out.in2 = ui.leaf({key = "in2", flags = {.Clickable, .Focusable}, props = {w = ui.Px(100), h = ui.Px(50)}})
	}
	return
}

scoped_tab :: proc(r: ^Rig) -> Scoped {
	key_down(r, .Tab)
	rig_open(r)
	f := scoped_form()
	ui.end_frame()
	key_up(r, .Tab)
	rig_open(r)
	scoped_form()
	ui.end_frame()
	return f
}

@(test)
test_tab_stays_inside_focus_scope :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, -1, -1)
	rig_open(&r)
	scoped_form()
	ui.end_frame()

	f := scoped_tab(&r)
	testing.expect_value(t, ui.focused().id, f.in1.id)
	scoped_tab(&r)
	testing.expect_value(t, ui.focused().id, f.in2.id)
	scoped_tab(&r)
	testing.expect_value(t, ui.focused().id, f.in1.id)
}

@(test)
test_reduce_motion_snaps_transitions :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)
	ui.set_reduce_motion(true)

	el := ui.Element {
		key        = "a",
		props      = {bg = RED},
		hover      = {bg = BLUE},
		transition = {props = {.Bg}, dur = 0.5},
	}
	one(el)
	el.state = {.Hover}
	testing.expect_value(t, bg_color(t, one(el)), BLUE)
	testing.expect(t, !ui.animating(), "no animation runs with reduced motion")
}

@(test)
test_hit_pad_grows_the_hit_area :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	build :: proc() -> ui.Interaction {
		ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Row}})
		ui.leaf({key = "gap", props = {w = ui.Px(100), h = ui.Px(50)}})
		return ui.leaf({key = "bar", flags = {.Clickable}, hit_pad = 4, props = {w = ui.Px(3), h = ui.Px(50)}})
	}

	r: Rig
	move(&r, 98, 10)
	it: ui.Interaction
	for _ in 0 ..< 3 {
		rig_open(&r)
		it = build()
		ui.end_frame()
	}
	testing.expect(t, it.hovered, "a point 2 px left of the bar hovers it")
	testing.expect_value(t, it.node.rect.w, 3)

	move(&r, 90, 10)
	for _ in 0 ..< 2 {
		rig_open(&r)
		it = build()
		ui.end_frame()
	}
	testing.expect(t, !it.hovered, "a point 10 px away does not")
}

@(test)
test_snap_state_is_instant_in_and_fades_out :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	el := ui.Element {
		key        = "a",
		props      = {opacity = 0},
		hover      = {opacity = 1},
		transition = {props = {.Opacity}, dur = 0.1, snap = {.Hover}},
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
	testing.expect_value(t, step(el), 1)
	el.state = {}
	v := step(el)
	testing.expect(t, v > 0 && v < 1, "the way out animates")
}

@(test)
test_focus_visible_follows_the_keyboard :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, -1, -1)
	rig_open(&r)
	form()
	ui.end_frame()

	f := tab(&r)
	testing.expect_value(t, ui.focused().id, f.a.id)
	testing.expect(t, .Focus_Visible in ui.focused().state, "a Tab shows the ring")

	move(&r, 50, 75)
	press(&r)
	rig_open(&r)
	form()
	ui.end_frame()
	release(&r)
	for _ in 0 ..< 2 {
		rig_open(&r)
		f = form()
		ui.end_frame()
	}
	testing.expect_value(t, ui.focused().id, f.b.id)
	testing.expect(t, .Focus_Visible not_in ui.focused().state, "a click does not")
}

@(test)
test_enter_props_fade_a_new_node_in :: proc(t: ^testing.T) {
	ctx: ui.Context
	styled(&ctx)
	defer ui.destroy(&ctx)

	el := ui.Element {
		key        = "a",
		props      = {opacity = 1},
		enter      = {opacity = 0},
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
	v := step(el)
	testing.expect(t, v > 0 && v < 1, "the node fades in")
	for _ in 0 ..< 10 {
		v = step(el)
	}
	testing.expect_value(t, v, 1)
}
