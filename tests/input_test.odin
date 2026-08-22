package tests

import "core:testing"
import ui "../loom"

DT :: f32(1.0 / 60.0)

Probe :: struct {
	cursor: ui.Cursor,
	calls:  int,
}

probe_backend :: proc(p: ^Probe) -> ui.Backend {
	b := fake_backend()
	b.user = p
	b.set_cursor = proc(c: ui.Cursor, user: rawptr) {
		q := (^Probe)(user)
		q.cursor = c
		q.calls += 1
	}
	return b
}

wired :: proc(ctx: ^ui.Context, cfg: ui.Config = {}, allocator := context.allocator) {
	c := cfg
	if c.backend.measure_run == nil {
		c.backend = fake_backend()
	}
	ui.init(ctx, c, allocator)
}

Rig :: struct {
	mouse:     ui.Vec2,
	down:      ui.Mouse_Set,
	keys:      ui.Key_Set,
	mods:      ui.Mod_Set,
	wheel:     ui.Vec2,
	prev_down: ui.Mouse_Set,
	prev_keys: ui.Key_Set,
}

rig_open :: proc(r: ^Rig, dt: f32 = DT) {
	in_ := ui.Input {
		dt             = dt,
		viewport       = VIEWPORT,
		dpi            = 1,
		mouse          = r.mouse,
		wheel          = r.wheel,
		mouse_down     = r.down,
		mouse_pressed  = r.down - r.prev_down,
		mouse_released = r.prev_down - r.down,
		keys_down      = r.keys,
		keys_pressed   = r.keys,
		mods           = r.mods,
	}
	ui.begin_frame(in_)
	r.prev_down = r.down
	r.prev_keys = r.keys
	r.wheel = {}
}

move :: proc(r: ^Rig, x, y: f32) {
	r.mouse = {x, y}
}

press :: proc(r: ^Rig, b: ui.Mouse_Button = .Left) {
	r.down += {b}
}

release :: proc(r: ^Rig, b: ui.Mouse_Button = .Left) {
	r.down -= {b}
}

key_down :: proc(r: ^Rig, k: ui.Key) {
	r.keys += {k}
}

key_up :: proc(r: ^Rig, k: ui.Key) {
	r.keys -= {k}
}

spin :: proc(r: ^Rig, x, y: f32) {
	r.wheel = {x, y}
}

Pair :: struct {
	a, b: ui.Interaction,
}

two_buttons :: proc() -> (out: Pair) {
	ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
	out.a = ui.leaf(
		{key = "a", flags = {.Clickable, .Focusable}, props = {w = ui.Px(100), h = ui.Px(50)}},
	)
	out.b = ui.leaf(
		{key = "b", flags = {.Clickable, .Focusable}, props = {w = ui.Px(100), h = ui.Px(50)}},
	)
	return
}

// ---- hit-testing and the one-frame contract ---------------------------------

@(test)
test_first_frame_reports_nothing :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 50, 25)
	press(&r)
	rig_open(&r)
	p := two_buttons()
	ui.end_frame()

	testing.expect(t, !p.a.hovered, "no hover on the first frame")
	testing.expect(t, !p.a.pressed, "no press on the first frame")
	testing.expect_value(t, p.a.rect, ui.Rect{})
}

@(test)
test_hover_lags_one_frame :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 50, 25)
	rig_open(&r)
	two_buttons()
	ui.end_frame()

	rig_open(&r)
	p := two_buttons()
	ui.end_frame()

	testing.expect(t, p.a.hovered, "a is hovered on the second frame")
	testing.expect(t, !p.b.hovered, "b is not hovered")
	testing.expect_value(t, p.a.rect, ui.Rect{0, 0, 100, 50})
	testing.expect(t, ui.wants_mouse(), "the pointer is over a loom node")
}

@(test)
test_interaction_reports_last_frame_geometry :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	shifted :: proc(off: f32) -> ui.Interaction {
		ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
		ui.leaf({key = "pad", props = {w = ui.Px(10), h = ui.Px(off)}})
		return ui.leaf(
			{key = "box", flags = {.Clickable}, props = {w = ui.Px(100), h = ui.Px(50)}},
		)
	}

	r: Rig
	move(&r, 50, 25)
	rig_open(&r)
	shifted(0)
	ui.end_frame()

	rig_open(&r)
	it := shifted(200)
	ui.end_frame()
	testing.expect(t, it.hovered, "still hovered at the old position")
	testing.expect_value(t, it.rect, ui.Rect{0, 0, 100, 50})

	rig_open(&r)
	it = shifted(200)
	ui.end_frame()
	testing.expect(t, !it.hovered, "the new position no longer covers the pointer")
	testing.expect_value(t, it.rect, ui.Rect{0, 200, 100, 50})
}

@(test)
test_plain_containers_are_transparent :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	panel :: proc() {
		ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600)}})
		ui.leaf({key = "panel", flags = {.Clip}, props = {w = ui.Px(200), h = ui.Px(200)}})
	}

	r: Rig
	move(&r, 50, 50)
	rig_open(&r)
	panel()
	ui.end_frame()

	rig_open(&r)
	panel()
	ui.end_frame()

	testing.expect(t, ui.hovered() == nil, "an inert clipping panel is not a hit target")
	testing.expect(t, !ui.wants_mouse(), "and does not claim the mouse")
}

@(test)
test_pass_through_is_not_a_target :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	build :: proc() -> ui.Interaction {
		ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600)}})
		return ui.leaf(
			{
				key = "ghost",
				flags = {.Clickable, .Pass_Through},
				props = {w = ui.Px(100), h = ui.Px(50)},
			},
		)
	}

	r: Rig
	move(&r, 50, 25)
	rig_open(&r)
	build()
	ui.end_frame()

	rig_open(&r)
	it := build()
	ui.end_frame()
	testing.expect(t, !it.hovered, "pass-through never hovers")
}

@(test)
test_topmost_z_wins_the_hit :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	build :: proc() -> Pair {
		ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600)}})
		lo := ui.leaf(
			{
				key = "lo",
				flags = {.Clickable},
				props = {
					position = .Absolute,
					inset = {l = 0, t = 0},
					w = ui.Px(100),
					h = ui.Px(100),
					z = 1,
				},
			},
		)
		hi := ui.leaf(
			{
				key = "hi",
				flags = {.Clickable},
				props = {
					position = .Absolute,
					inset = {l = 0, t = 0},
					w = ui.Px(100),
					h = ui.Px(100),
					z = 5,
				},
			},
		)
		return {lo, hi}
	}

	r: Rig
	move(&r, 50, 50)
	rig_open(&r)
	build()
	ui.end_frame()

	rig_open(&r)
	p := build()
	ui.end_frame()
	testing.expect(t, p.b.hovered, "the higher z wins")
	testing.expect(t, !p.a.hovered, "the lower z does not")
}

@(test)
test_clipped_out_child_is_not_hit :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	build :: proc() -> ui.Interaction {
		ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600)}})
		ui.scope(
			{
				key = "list",
				flags = {.Clip},
				props = {w = ui.Px(200), h = ui.Px(60), dir = .Column},
			},
		)
		ui.leaf({key = "r0", flags = {.Clickable}, props = {w = ui.STRETCH, h = ui.Px(60)}})
		return ui.leaf(
			{key = "r1", flags = {.Clickable}, props = {w = ui.STRETCH, h = ui.Px(60)}},
		)
	}

	r: Rig
	move(&r, 50, 90)
	rig_open(&r)
	build()
	ui.end_frame()

	rig_open(&r)
	it := build()
	ui.end_frame()
	testing.expect(t, !it.hovered, "the row below the clip box is not hit")
}

@(test)
test_disabled_subtree_is_not_hit :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	build :: proc() -> ui.Interaction {
		ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600)}})
		ui.scope({key = "off", flags = {.Disabled}, props = {w = ui.Px(200), h = ui.Px(200)}})
		return ui.leaf(
			{key = "btn", flags = {.Clickable}, props = {w = ui.Px(100), h = ui.Px(50)}},
		)
	}

	r: Rig
	move(&r, 50, 25)
	for _ in 0 ..< 3 {
		rig_open(&r)
		build()
		ui.end_frame()
	}

	rig_open(&r)
	it := build()
	ui.end_frame()
	testing.expect(t, !it.hovered, "a disabled subtree does not hit-test")
}

// ---- press, click, drag, capture --------------------------------------------

@(test)
test_click_needs_press_and_release_on_the_same_node :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 50, 25)
	rig_open(&r)
	two_buttons()
	ui.end_frame()

	press(&r)
	rig_open(&r)
	p := two_buttons()
	ui.end_frame()
	testing.expect(t, p.a.pressed, "pressed on the press frame")
	testing.expect(t, !p.a.clicked, "not clicked yet")

	rig_open(&r)
	p = two_buttons()
	ui.end_frame()
	testing.expect(t, !p.a.pressed, "pressed is a one-frame edge")

	release(&r)
	rig_open(&r)
	p = two_buttons()
	ui.end_frame()
	testing.expect(t, p.a.released, "released on the release frame")
	testing.expect(t, p.a.clicked, "click completes")

	rig_open(&r)
	p = two_buttons()
	ui.end_frame()
	testing.expect(t, !p.a.clicked, "clicked is a one-frame edge")
}

@(test)
test_dragging_off_cancels_the_click :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 50, 25)
	rig_open(&r)
	two_buttons()
	ui.end_frame()

	press(&r)
	rig_open(&r)
	two_buttons()
	ui.end_frame()

	move(&r, 50, 75)
	release(&r)
	rig_open(&r)
	p := two_buttons()
	ui.end_frame()
	testing.expect(t, !p.a.clicked, "releasing off the press target is not a click")
	testing.expect(t, !p.b.clicked, "and does not click the node underneath either")
}

@(test)
test_active_follows_the_press_target :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 50, 25)
	rig_open(&r)
	two_buttons()
	ui.end_frame()

	press(&r)
	rig_open(&r)
	two_buttons()
	ui.end_frame()

	move(&r, 50, 75)
	rig_open(&r)
	p := two_buttons()
	ui.end_frame()

	testing.expect(t, .Active in p.a.node.state, "a stays active while held")
	testing.expect(t, .Hover in p.b.node.state, "b is hovered")
	testing.expect(t, .Active not_in p.b.node.state, "b is not active")
}

@(test)
test_right_click_is_separate :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 50, 25)
	rig_open(&r)
	two_buttons()
	ui.end_frame()

	press(&r, .Right)
	rig_open(&r)
	two_buttons()
	ui.end_frame()

	release(&r, .Right)
	rig_open(&r)
	p := two_buttons()
	ui.end_frame()
	testing.expect(t, p.a.right_clicked, "right click fires")
	testing.expect(t, !p.a.clicked, "left click does not")
}

double_click_run :: proc(r: ^Rig, gap: f32, steps: int) -> bool {
	rig_open(r, 0)
	two_buttons()
	ui.end_frame()

	press(r)
	rig_open(r, 0)
	two_buttons()
	ui.end_frame()

	release(r)
	rig_open(r, 0)
	two_buttons()
	ui.end_frame()

	for _ in 0 ..< steps {
		rig_open(r, gap)
		two_buttons()
		ui.end_frame()
	}

	press(r)
	rig_open(r, 0)
	two_buttons()
	ui.end_frame()

	release(r)
	rig_open(r, 0)
	p := two_buttons()
	ui.end_frame()
	return p.a.double_clicked
}

@(test)
test_double_click_at_the_boundary :: proc(t: ^testing.T) {
	hit: ui.Context
	wired(&hit, ui.Config{double_click = 0.5})
	r: Rig
	move(&r, 50, 25)
	testing.expect(t, double_click_run(&r, 0.5, 1), "a gap of exactly double_click still counts")
	ui.destroy(&hit)

	miss: ui.Context
	wired(&miss, ui.Config{double_click = 0.5})
	r2: Rig
	move(&r2, 50, 25)
	testing.expect(t, !double_click_run(&r2, 0.75, 1), "a longer gap does not")
	ui.destroy(&miss)
}

@(test)
test_double_click_uses_dt_not_a_wall_clock :: proc(t: ^testing.T) {
	hit: ui.Context
	wired(&hit, ui.Config{double_click = 0.5})
	r: Rig
	move(&r, 50, 25)
	testing.expect(t, double_click_run(&r, 0.25, 2), "two quarter-second frames still count")
	ui.destroy(&hit)

	miss: ui.Context
	wired(&miss, ui.Config{double_click = 0.5})
	r2: Rig
	move(&r2, 50, 25)
	testing.expect(t, !double_click_run(&r2, 0.25, 4), "four do not, at the same wall clock")
	ui.destroy(&miss)
}

@(test)
test_double_click_needs_the_same_position :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx, ui.Config{double_click = 0.5})
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 20, 25)
	rig_open(&r, 0)
	two_buttons()
	ui.end_frame()

	press(&r)
	rig_open(&r, 0)
	two_buttons()
	ui.end_frame()
	release(&r)
	rig_open(&r, 0)
	two_buttons()
	ui.end_frame()

	move(&r, 80, 25)
	press(&r)
	rig_open(&r, 0)
	two_buttons()
	ui.end_frame()
	release(&r)
	rig_open(&r, 0)
	p := two_buttons()
	ui.end_frame()

	testing.expect(t, p.a.clicked, "the second click still lands")
	testing.expect(t, !p.a.double_clicked, "but too far away to be a double click")
}

draggable :: proc() -> ui.Interaction {
	ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
	it := ui.leaf(
		{key = "knob", flags = {.Draggable}, props = {w = ui.Px(100), h = ui.Px(50)}},
	)
	ui.leaf({key = "under", flags = {.Clickable}, props = {w = ui.Px(800), h = ui.Px(500)}})
	return it
}

@(test)
test_drag_dead_zone :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 50, 25)
	rig_open(&r)
	draggable()
	ui.end_frame()

	press(&r)
	rig_open(&r)
	draggable()
	ui.end_frame()

	move(&r, 52, 25)
	rig_open(&r)
	it := draggable()
	ui.end_frame()
	testing.expect(t, !it.dragging, "2 px is inside the dead zone")

	move(&r, 56, 25)
	rig_open(&r)
	it = draggable()
	ui.end_frame()
	testing.expect(t, it.dragging, "6 px starts the drag")
	testing.expect_value(t, it.drag_delta, ui.Vec2{6, 0})
	testing.expect_value(t, it.drag_start, ui.Vec2{50, 25})

	move(&r, 59, 25)
	rig_open(&r)
	it = draggable()
	ui.end_frame()
	testing.expect_value(t, it.drag_delta, ui.Vec2{3, 0})
}

@(test)
test_capture_routes_to_one_node :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 50, 25)
	rig_open(&r)
	draggable()
	ui.end_frame()

	press(&r)
	rig_open(&r)
	draggable()
	ui.end_frame()

	move(&r, 400, 400)
	rig_open(&r)
	it := draggable()
	ui.end_frame()
	testing.expect(t, it.dragging, "the drag survives leaving the rect")
	testing.expect(t, it.hovered, "capture keeps the hover on the captured node")
	testing.expect(t, ui.wants_mouse(), "capture claims the mouse")

	release(&r)
	rig_open(&r)
	it = draggable()
	ui.end_frame()
	testing.expect(t, !it.dragging, "releasing outside ends the drag")

	rig_open(&r)
	it = draggable()
	ui.end_frame()
	testing.expect(t, !it.hovered, "and capture is gone")
}

// ---- focus -------------------------------------------------------------------

Form :: struct {
	a, b, c, d: ui.Interaction,
}

form :: proc(disable_c := false) -> (out: Form) {
	ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
	out.a = ui.leaf(
		{key = "a", flags = {.Clickable, .Focusable}, props = {w = ui.Px(100), h = ui.Px(50)}},
	)
	{
		ui.scope({key = "row", props = {w = ui.Px(400), h = ui.Px(50), dir = .Row}})
		out.b = ui.leaf(
			{
				key = "b",
				flags = {.Clickable, .Focusable},
				props = {w = ui.Px(100), h = ui.Px(50)},
			},
		)
		cf := ui.Flags{.Clickable, .Focusable}
		if disable_c {
			cf += {.Disabled}
		}
		out.c = ui.leaf({key = "c", flags = cf, props = {w = ui.Px(100), h = ui.Px(50)}})
	}
	ui.leaf({key = "plain", props = {w = ui.Px(100), h = ui.Px(50)}})
	out.d = ui.leaf(
		{key = "d", flags = {.Clickable, .Focusable}, props = {w = ui.Px(100), h = ui.Px(50)}},
	)
	return
}

tab :: proc(r: ^Rig, disable_c := false) -> Form {
	key_down(r, .Tab)
	rig_open(r)
	f := form(disable_c)
	ui.end_frame()
	key_up(r, .Tab)
	rig_open(r)
	form(disable_c)
	ui.end_frame()
	return f
}

@(test)
test_tab_walks_the_form_in_call_order :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, -1, -1)
	rig_open(&r)
	f := form()
	ui.end_frame()

	order := [4]ui.Id{f.a.id, f.b.id, f.c.id, f.d.id}
	for want in order {
		tab(&r)
		testing.expect_value(t, ui.focused().id, want)
	}
	tab(&r)
	testing.expect_value(t, ui.focused().id, order[0])
}

@(test)
test_shift_tab_reverses_and_wraps :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, -1, -1)
	rig_open(&r)
	f := form()
	ui.end_frame()

	r.mods += {.Shift}
	tab(&r)
	testing.expect_value(t, ui.focused().id, f.d.id)
	tab(&r)
	testing.expect_value(t, ui.focused().id, f.c.id)
}

@(test)
test_tab_skips_disabled :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, -1, -1)
	for _ in 0 ..< 3 {
		rig_open(&r)
		form(true)
		ui.end_frame()
	}

	f := tab(&r, true)
	testing.expect_value(t, ui.focused().id, f.a.id)
	tab(&r, true)
	testing.expect_value(t, ui.focused().id, f.b.id)
	tab(&r, true)
	testing.expect_value(t, ui.focused().id, f.d.id)
}

@(test)
test_escape_clears_focus :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, -1, -1)
	rig_open(&r)
	form()
	ui.end_frame()

	tab(&r)
	testing.expect(t, ui.focused() != nil, "tab focused something")

	key_down(&r, .Escape)
	rig_open(&r)
	form()
	ui.end_frame()
	testing.expect(t, ui.focused() == nil, "escape clears focus")
}

@(test)
test_click_focuses_and_clicking_outside_clears :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	nested :: proc() -> Pair {
		ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
		field := ui.begin(
			{
				key = "field",
				flags = {.Clickable, .Focusable},
				props = {w = ui.Px(200), h = ui.Px(50), dir = .Row},
			},
		)
		ui.leaf({key = "caret", flags = {.Clickable}, props = {w = ui.Px(20), h = ui.Px(50)}})
		ui.end()
		other := ui.leaf(
			{key = "other", flags = {.Clickable}, props = {w = ui.Px(200), h = ui.Px(50)}},
		)
		return {field, other}
	}

	click :: proc(r: ^Rig, x, y: f32) {
		move(r, x, y)
		press(r)
		rig_open(r)
		nested()
		ui.end_frame()
		release(r)
		rig_open(r)
		nested()
		ui.end_frame()
	}

	r: Rig
	move(&r, -1, -1)
	rig_open(&r)
	p := nested()
	ui.end_frame()

	click(&r, 100, 25)
	testing.expect_value(t, ui.focused().id, p.a.id)

	click(&r, 10, 25)
	testing.expect_value(t, ui.focused().id, p.a.id)

	click(&r, 100, 75)
	testing.expect(t, ui.focused() == nil, "clicking outside clears focus")
}

@(test)
test_focus_within_lands_on_ancestors :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, -1, -1)
	rig_open(&r)
	form()
	ui.end_frame()

	tab(&r)
	tab(&r)

	rig_open(&r)
	f := form()
	ui.end_frame()

	testing.expect(t, .Focus in f.b.node.state, "b has focus")
	row := f.b.node.parent
	testing.expect(t, .Focus_Within in row.state, "the row has focus-within")
	testing.expect(t, .Focus_Within in row.parent.state, "and so does its parent")
	testing.expect(t, .Focus_Within not_in f.b.node.state, "but the focused node does not")
}

@(test)
test_set_focus_applies_next_frame :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, -1, -1)
	rig_open(&r)
	f := form()
	ui.set_focus(f.c.id)
	ui.end_frame()
	testing.expect(t, ui.focused() == nil, "set_focus is deferred")

	rig_open(&r)
	form()
	ui.end_frame()
	testing.expect_value(t, ui.focused().id, f.c.id)
}

@(test)
test_pruned_focus_falls_to_nothing :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, -1, -1)
	rig_open(&r)
	form()
	ui.end_frame()
	tab(&r)
	testing.expect(t, ui.focused() != nil, "focused before the node vanishes")

	for _ in 0 ..< 5 {
		rig_open(&r)
		ui.begin({key = "root", props = {w = ui.Px(800), h = ui.Px(600)}})
		ui.end()
		ui.end_frame()
	}
	testing.expect(t, ui.focused() == nil, "focus does not survive pruning")
}

@(test)
test_space_activates_a_focused_button :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, -1, -1)
	rig_open(&r)
	form()
	ui.end_frame()
	tab(&r)

	key_down(&r, .Space)
	rig_open(&r)
	f := form()
	ui.end_frame()
	testing.expect(t, f.a.pressed, "space presses the focused button")
	testing.expect(t, !f.a.clicked, "but does not click it yet")

	rig_open(&r)
	f = form()
	ui.end_frame()
	testing.expect(t, !f.a.pressed, "auto-repeat does not re-press")
	testing.expect(t, !f.a.clicked, "and does not click while held")
	testing.expect(t, .Active in f.a.node.state, "the button stays depressed")

	key_up(&r, .Space)
	rig_open(&r)
	f = form()
	ui.end_frame()
	testing.expect(t, f.a.clicked, "releasing the key clicks once")

	rig_open(&r)
	f = form()
	ui.end_frame()
	testing.expect(t, !f.a.clicked, "and only once")
}

@(test)
test_text_input_swallows_space :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	field :: proc() -> ui.Interaction {
		ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600)}})
		return ui.leaf(
			{
				key = "field",
				flags = {.Clickable, .Focusable, .Text_Input},
				props = {w = ui.Px(200), h = ui.Px(50)},
			},
		)
	}

	r: Rig
	move(&r, -1, -1)
	rig_open(&r)
	it := field()
	ui.end_frame()

	ui.set_focus(it.id)
	rig_open(&r)
	field()
	ui.end_frame()
	testing.expect(t, ui.wants_keyboard(), "a focused text input wants the keyboard")

	key_down(&r, .Space)
	rig_open(&r)
	it = field()
	ui.end_frame()
	testing.expect(t, !it.pressed, "space does not activate a text input")
	testing.expect(t, !it.clicked, "and never clicks it")
}

@(test)
test_wants_keyboard_is_false_for_a_button :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, -1, -1)
	rig_open(&r)
	form()
	ui.end_frame()
	tab(&r)

	testing.expect(t, ui.focused() != nil, "a button has focus")
	testing.expect(t, !ui.wants_keyboard(), "but does not want the keyboard")
}

// ---- scrolling ---------------------------------------------------------------

List :: struct {
	list: ui.Interaction,
	rows: [10]ui.Interaction,
}

scroll_list :: proc() -> (out: List) {
	ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600)}})
	out.list = ui.begin(
		{
			key = "list",
			flags = {.Scroll_Y},
			props = {w = ui.Px(200), h = ui.Px(100), dir = .Column},
		},
	)
	for i in 0 ..< 10 {
		ui.push_id_int(i64(i))
		out.rows[i] = ui.leaf({flags = {.Clickable}, props = {w = ui.STRETCH, h = ui.Px(30)}})
		ui.pop_id()
	}
	ui.end()
	return
}

@(test)
test_wheel_scrolls_the_innermost_scrollable :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx, ui.Config{scroll_speed = 40, no_scroll_inertia = true})
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 50, 50)
	rig_open(&r)
	scroll_list()
	ui.end_frame()

	spin(&r, 0, 1)
	rig_open(&r)
	l := scroll_list()
	ui.end_frame()

	testing.expect_value(t, l.list.node.scroll.y, f32(40))
	testing.expect_value(t, l.list.wheel.y, f32(40))
	testing.expect(t, l.rows[1].wheel.y == 0, "the row under the pointer did not consume it")
}

@(test)
test_shift_wheel_maps_to_x :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx, ui.Config{scroll_speed = 40, no_scroll_inertia = true})
	defer ui.destroy(&ctx)

	wide :: proc() -> ui.Interaction {
		ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600)}})
		it := ui.begin(
			{
				key = "strip",
				flags = {.Scroll_X},
				props = {w = ui.Px(200), h = ui.Px(100), dir = .Row},
			},
		)
		ui.leaf({key = "wide", props = {w = ui.Px(1000), h = ui.Px(50)}})
		ui.end()
		return it
	}

	r: Rig
	move(&r, 50, 50)
	rig_open(&r)
	wide()
	ui.end_frame()

	r.mods += {.Shift}
	spin(&r, 0, 1)
	rig_open(&r)
	it := wide()
	ui.end_frame()

	testing.expect_value(t, it.node.scroll.x, f32(40))
	testing.expect_value(t, it.node.scroll.y, f32(0))
}

nested_lists :: proc() -> Pair {
	ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600)}})
	outer := ui.begin(
		{
			key = "outer",
			flags = {.Scroll_Y},
			props = {w = ui.Px(300), h = ui.Px(200), dir = .Column},
		},
	)
	inner := ui.begin(
		{
			key = "inner",
			flags = {.Scroll_Y},
			props = {w = ui.Px(200), h = ui.Px(100), dir = .Column},
		},
	)
	ui.leaf({key = "tall_in", props = {w = ui.STRETCH, h = ui.Px(200)}})
	ui.end()
	ui.leaf({key = "tall_out", props = {w = ui.STRETCH, h = ui.Px(400)}})
	ui.end()
	return {outer, inner}
}

@(test)
test_nested_scroll_falls_through_at_the_limit :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx, ui.Config{scroll_speed = 100, no_scroll_inertia = true})
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 50, 50)
	rig_open(&r)
	nested_lists()
	ui.end_frame()

	spin(&r, 0, 1)
	rig_open(&r)
	p := nested_lists()
	ui.end_frame()
	testing.expect_value(t, p.b.node.scroll.y, f32(100))
	testing.expect_value(t, p.a.node.scroll.y, f32(0))

	spin(&r, 0, 1)
	rig_open(&r)
	p = nested_lists()
	ui.end_frame()
	testing.expect_value(t, p.b.node.scroll.y, f32(100))
	testing.expect_value(t, p.a.node.scroll.y, f32(100))
}

@(test)
test_scroll_speed_is_applied :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx, ui.Config{scroll_speed = 7, no_scroll_inertia = true})
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 50, 50)
	rig_open(&r)
	scroll_list()
	ui.end_frame()

	spin(&r, 0, 2)
	rig_open(&r)
	l := scroll_list()
	ui.end_frame()
	testing.expect_value(t, l.list.node.scroll.y, f32(14))
}

@(test)
test_inertia_decays_and_stops :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx, ui.Config{scroll_speed = 20})
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 50, 50)
	rig_open(&r)
	scroll_list()
	ui.end_frame()

	spin(&r, 0, 1)
	rig_open(&r)
	l := scroll_list()
	ui.end_frame()
	after_wheel := l.list.node.scroll.y
	testing.expect(t, ui.animating(), "a fling keeps the host drawing")

	prev := after_wheel
	settled := false
	for _ in 0 ..< 200 {
		rig_open(&r)
		l = scroll_list()
		ui.end_frame()
		testing.expect(t, l.list.node.scroll.y >= prev, "inertia only moves forward")
		prev = l.list.node.scroll.y
		if !ui.animating() {
			settled = true
			break
		}
	}
	testing.expect(t, settled, "inertia settles")
	testing.expect(t, prev > after_wheel, "inertia carried the list further")
}

@(test)
test_inertia_opt_out :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx, ui.Config{scroll_speed = 20, no_scroll_inertia = true})
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 50, 50)
	rig_open(&r)
	scroll_list()
	ui.end_frame()

	spin(&r, 0, 1)
	rig_open(&r)
	l := scroll_list()
	ui.end_frame()
	at := l.list.node.scroll.y
	testing.expect(t, !ui.animating(), "no inertia means nothing to animate")

	rig_open(&r)
	l = scroll_list()
	ui.end_frame()
	testing.expect_value(t, l.list.node.scroll.y, at)
}

@(test)
test_inertia_dies_at_the_clamp :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx, ui.Config{scroll_speed = 400})
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 50, 50)
	rig_open(&r)
	scroll_list()
	ui.end_frame()

	spin(&r, 0, 4)
	rig_open(&r)
	scroll_list()
	ui.end_frame()

	settled := false
	for _ in 0 ..< 10 {
		rig_open(&r)
		l := scroll_list()
		ui.end_frame()
		testing.expect(t, l.list.node.scroll.y <= 200, "never past the limit")
		if !ui.animating() {
			settled = true
			break
		}
	}
	testing.expect(t, settled, "the fling dies at the bottom instead of spinning")
}

@(test)
test_scroll_to_brings_a_row_into_view :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx, ui.Config{no_scroll_inertia = true})
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, -1, -1)
	rig_open(&r)
	l := scroll_list()
	ui.end_frame()

	rig_open(&r)
	l = scroll_list()
	ui.scroll_to(l.rows[9].id, false)
	ui.end_frame()
	testing.expect_value(t, l.list.node.scroll.y, f32(200))

	rig_open(&r)
	l = scroll_list()
	ui.scroll_to(l.rows[0].id, false)
	ui.end_frame()
	testing.expect_value(t, l.list.node.scroll.y, f32(0))

	rig_open(&r)
	l = scroll_list()
	ui.scroll_to(l.rows[1].id, false)
	ui.end_frame()
	testing.expect_value(t, l.list.node.scroll.y, f32(0))
}

@(test)
test_scroll_to_animated_eases_over_frames :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx, ui.Config{scroll_to_dur = 0.25, no_scroll_inertia = true})
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, -1, -1)
	rig_open(&r)
	l := scroll_list()
	ui.end_frame()

	rig_open(&r)
	l = scroll_list()
	ui.scroll_to(l.rows[9].id, true)
	ui.end_frame()
	testing.expect_value(t, l.list.node.scroll.y, f32(0))

	prev := f32(0)
	settled := false
	for _ in 0 ..< 60 {
		rig_open(&r)
		l = scroll_list()
		ui.end_frame()
		testing.expect(t, l.list.node.scroll.y >= prev, "the tween is monotone")
		prev = l.list.node.scroll.y
		if !ui.animating() {
			settled = true
			break
		}
	}
	testing.expect(t, settled, "the tween finishes")
	testing.expect_value(t, prev, f32(200))
}

// ---- host queries ------------------------------------------------------------

@(test)
test_cursor_is_pushed_once_per_change :: proc(t: ^testing.T) {
	p: Probe
	ctx: ui.Context
	wired(&ctx, ui.Config{backend = probe_backend(&p)})
	defer ui.destroy(&ctx)

	build :: proc() -> ui.Interaction {
		ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600)}})
		return ui.leaf(
			{
				key = "btn",
				flags = {.Clickable},
				props = {w = ui.Px(100), h = ui.Px(50), cursor = .Pointer},
			},
		)
	}

	r: Rig
	move(&r, -1, -1)
	rig_open(&r)
	build()
	ui.end_frame()
	testing.expect_value(t, p.cursor, ui.Cursor.Default)
	testing.expect_value(t, p.calls, 1)

	move(&r, 50, 25)
	rig_open(&r)
	build()
	ui.end_frame()
	testing.expect_value(t, p.cursor, ui.Cursor.Pointer)
	testing.expect_value(t, p.calls, 2)

	rig_open(&r)
	build()
	ui.end_frame()
	testing.expect_value(t, p.calls, 2)

	rig_open(&r)
	build()
	ui.set_cursor(.Text)
	ui.end_frame()
	testing.expect_value(t, p.cursor, ui.Cursor.Text)
	testing.expect_value(t, p.calls, 3)

	rig_open(&r)
	build()
	ui.end_frame()
	testing.expect_value(t, p.cursor, ui.Cursor.Pointer)
	testing.expect_value(t, p.calls, 4)
}
