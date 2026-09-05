package tests

import "core:testing"
import ui "../loom"

// Opens a frame whose only input is the ordered key stream.
open_evs :: proc(evs: []ui.Key_Event, dt: f32 = DT) {
	ui.begin_frame(ui.Input{dt = dt, viewport = VIEWPORT, dpi = 1, key_events = evs})
}

nest :: proc() -> (outer, inner: ui.Interaction) {
	outer = ui.begin({key = "outer", props = {w = ui.Px(200), h = ui.Px(200)}})
	inner = ui.leaf(
		{key = "inner", flags = {.Clickable, .Focusable}, props = {w = ui.Px(100), h = ui.Px(50)}},
	)
	ui.end()
	return
}

// ---- the key stream ---------------------------------------------------------

@(test)
test_key_events_fold_into_the_level_sets :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	open_evs({{key = .F5, action = .Press}, {key = .Left_Bracket, action = .Press}})
	testing.expect(t, ui.key_pressed(.F5), "a press in the stream reads as pressed")
	testing.expect(t, ui.key_held(.Left_Bracket), "a press in the stream reads as held")
	ui.end_frame()

	open_evs({{key = .F5, action = .Release}})
	testing.expect(t, !ui.key_held(.F5), "a release in the stream clears the held bit")
	ui.end_frame()
}

@(test)
test_take_key_consumes_the_event :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	open_evs({{key = .S, mods = {.Ctrl}, action = .Press}})
	testing.expect(t, ui.take_key(.S, {.Ctrl}), "the first reader takes it")
	testing.expect(t, !ui.take_key(.S, {.Ctrl}), "a later reader does not see it again")
	ui.end_frame()
}

@(test)
test_take_key_matches_the_whole_modifier_set :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	open_evs({{key = .S, mods = {.Ctrl, .Shift}, action = .Press}})
	testing.expect(t, !ui.take_key(.S, {.Ctrl}), "a smaller modifier set does not match")
	testing.expect(t, ui.take_key(.S, {.Ctrl, .Shift}), "the exact set matches")
	ui.end_frame()
}

@(test)
test_take_key_takes_a_repeat_but_never_a_release :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	open_evs({{key = .Down, action = .Release}, {key = .Down, action = .Repeat}})
	testing.expect(t, ui.take_key(.Down), "a repeat is taken, the release before it is skipped")
	testing.expect(t, !ui.take_key(.Down), "the release stays in the stream")
	ui.end_frame()
}

@(test)
test_the_key_stream_is_live :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	open_evs({{key = .P, mods = {.Ctrl}, action = .Press}})
	for &ev in ui.keys() {
		ev.consumed = true
	}
	testing.expect(t, !ui.take_key(.P, {.Ctrl}), "a hook that consumes hides the event")
	ui.end_frame()
}

// ---- hover edges, click count, focus ----------------------------------------

@(test)
test_hover_reports_enter_and_exit_once :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	p: Pair
	move(&r, 50, 25)
	// The first frame has no rects yet, so hover lands on the second.
	for _ in 0 ..< 2 {
		rig_open(&r)
		p = two_buttons()
		ui.end_frame()
	}
	testing.expect(t, p.a.hovered, "the pointer is over a")
	testing.expect(t, p.a.hover_entered, "the frame the hover starts reports entered")

	rig_open(&r)
	p = two_buttons()
	ui.end_frame()
	testing.expect(t, p.a.hovered, "the pointer stays over a")
	testing.expect(t, !p.a.hover_entered, "entered is only the first frame")

	move(&r, 50, 80)
	rig_open(&r)
	p = two_buttons()
	ui.end_frame()
	testing.expect(t, p.a.hover_exited, "a reports the exit")
	testing.expect(t, p.b.hover_entered, "b reports the enter")
}

@(test)
test_click_count_counts_a_triple_click :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	p: Pair
	move(&r, 50, 25)
	for _ in 0 ..< 2 {
		rig_open(&r)
		p = two_buttons()
		ui.end_frame()
	}

	counts: [3]int
	for i in 0 ..< 3 {
		press(&r)
		rig_open(&r)
		p = two_buttons()
		ui.end_frame()

		release(&r)
		rig_open(&r)
		p = two_buttons()
		ui.end_frame()
		counts[i] = p.a.click_count
	}

	testing.expect_value(t, counts[0], 1)
	testing.expect_value(t, counts[1], 2)
	testing.expect_value(t, counts[2], 3)
}

@(test)
test_focus_within_sees_a_focused_descendant :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 50, 25)
	outer, inner: ui.Interaction
	for _ in 0 ..< 2 {
		rig_open(&r)
		outer, inner = nest()
		ui.end_frame()
	}

	press(&r)
	rig_open(&r)
	outer, inner = nest()
	within := ui.focus_within(outer.node)
	ui.end_frame()

	testing.expect(t, inner.focused, "the child took the focus")
	testing.expect(t, within, "the parent sees the focus inside it")
	testing.expect(t, !ui.focus_within(nil), "a nil node is never focused within")
}
