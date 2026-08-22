package tests

import "core:testing"
import ui "../loom"

// ---- merge_element ----

@(test)
test_merge_element_caller_key_and_flags :: proc(t: ^testing.T) {
	dst := ui.Element {
		key   = "widget",
		flags = {.Clickable},
		props = {w = ui.Px(10), h = ui.Px(20)},
	}
	ui.merge_element(&dst, {key = "mine", flags = {.Focusable}, props = {w = ui.Px(99)}})

	testing.expect_value(t, dst.key, "mine")
	testing.expect(t, dst.flags == {.Clickable, .Focusable}, "flags are OR'd, never subtracted")
	testing.expect_value(t, dst.props.w, ui.Size(ui.Px(99)))
	testing.expect_value(t, dst.props.h, ui.Size(ui.Px(20)))
}

@(test)
test_merge_element_cannot_remove_a_flag :: proc(t: ^testing.T) {
	dst := ui.Element {
		flags = {.Clickable, .Focusable},
	}
	ui.merge_element(&dst, {flags = {}})
	testing.expect(t, .Clickable in dst.flags, "a caller cannot strip .Clickable")
}

@(test)
test_merge_element_partial_variant_override :: proc(t: ^testing.T) {
	dst := ui.Element {
		hover = {bg = RED, border = {width = ui.all(2), color = GREEN}},
	}
	ui.merge_element(&dst, {hover = {bg = BLUE}})

	testing.expect_value(t, dst.hover.bg.(ui.Color), BLUE)
	testing.expect_value(t, dst.hover.border.color, GREEN)
	testing.expect_value(t, dst.hover.border.width.l, f32(2))
}

@(test)
test_merge_element_clear_removes_a_default :: proc(t: ^testing.T) {
	dst := ui.Element {
		props = {bg = RED},
		hover = {bg = GREEN},
	}
	ui.merge_element(&dst, {hover = {clear = {.Bg}}})
	testing.expect(t, dst.hover.bg == nil, "clear erases the widget's own hover default")
	testing.expect_value(t, dst.props.bg.(ui.Color), RED)
}

@(test)
test_merge_element_does_not_mutate_the_caller :: proc(t: ^testing.T) {
	over := ui.Element {
		key   = "mine",
		flags = {.Focusable},
		props = {w = ui.Px(5)},
		hover = {bg = BLUE},
	}
	before := over
	dst := ui.Element {
		flags = {.Clickable},
		props = {w = ui.Px(1), h = ui.Px(2)},
		hover = {bg = RED, color = GREEN},
	}
	ui.merge_element(&dst, over)
	testing.expect(t, over.key == before.key, "the caller's key is untouched")
	testing.expect(t, over.flags == before.flags, "the caller's flags are untouched")
	testing.expect(t, over.props.w == before.props.w, "the caller's props are untouched")
	testing.expect(t, over.hover.bg.(ui.Color) == before.hover.bg.(ui.Color), "the caller's variants are untouched")
}

@(test)
test_merge_element_rules_concatenate_widget_first :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	widget_rules := []ui.Rule{{on = {.Checked}, props = {bg = RED}}}
	caller_rules := []ui.Rule{{on = {.Checked}, props = {bg = BLUE}}}

	dst := ui.Element {
		rules = widget_rules,
	}
	ui.merge_element(&dst, {rules = caller_rules})

	testing.expect_value(t, len(dst.rules), 2)
	testing.expect_value(t, dst.rules[0].props.bg.(ui.Color), RED)
	testing.expect_value(t, dst.rules[1].props.bg.(ui.Color), BLUE)
	ui.end_frame()
}

@(test)
test_merge_element_transition_replaced_wholesale :: proc(t: ^testing.T) {
	dst := ui.Element {
		transition = {props = {.Bg, .Radius}, dur = 0.5, ease = .Out_Back},
	}
	ui.merge_element(&dst, {transition = {props = {.Opacity}, dur = 0.1}})
	testing.expect(t, dst.transition.props == {.Opacity}, "a Transition is one unit")
	testing.expect_value(t, dst.transition.dur, f32(0.1))
	testing.expect(t, dst.transition.ease == .Linear, "ease comes from the caller's transition")
}

// ---- label, spacer, divider ----

@(test)
test_label_fits_its_text :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	it: ui.Interaction
	open_frame()
	{
		ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
		it = ui.label("abcd", {key = "l"})
	}
	ui.end_frame()

	expect_rect(t, it.node, 0, 0, 4 * CHAR_W, 16)
}

@(test)
test_spacer_eats_leftover_main_axis_space :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	tail: ui.Interaction
	open_frame()
	{
		ui.scope({key = "root", props = {w = ui.Px(200), h = ui.Px(100), dir = .Column}})
		ui.leaf({key = "head", props = {w = ui.STRETCH, h = ui.Px(20)}})
		ui.spacer()
		tail = ui.leaf({key = "tail", props = {w = ui.STRETCH, h = ui.Px(20)}})
	}
	ui.end_frame()

	expect_rect(t, tail.node, 0, 80, 200, 20)
}

@(test)
test_divider_picks_its_axis_from_the_parent :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	col, row: ui.Interaction
	open_frame()
	{
		ui.scope({key = "root", props = {w = ui.Px(200), h = ui.Px(100), dir = .Column}})
		{
			ui.scope({key = "c", props = {w = ui.Px(200), h = ui.Px(40), dir = .Column}})
			col = ui.divider({key = "d1"})
		}
		{
			ui.scope({key = "r", props = {w = ui.Px(200), h = ui.Px(40), dir = .Row}})
			row = ui.divider({key = "d2"})
		}
	}
	ui.end_frame()

	testing.expect_value(t, col.node.rect.h, f32(1))
	testing.expect_value(t, col.node.rect.w, f32(200))
	testing.expect_value(t, row.node.rect.w, f32(1))
	testing.expect_value(t, row.node.rect.h, f32(40))
	testing.expect_value(t, col.node.computed.bg.(ui.Color), ui.theme().divider)
}

// ---- button ----

one_button :: proc(el: ui.Element = {}) -> ui.Interaction {
	ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
	e := el
	e.key = "btn"
	return ui.button("Go", e)
}

@(test)
test_button_clicks_and_uses_the_accent_slot :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 5, 5)
	rig_open(&r)
	it := one_button()
	ui.end_frame()
	testing.expect_value(t, it.node.computed.bg.(ui.Color), ui.theme().accent)

	press(&r)
	rig_open(&r)
	one_button()
	ui.end_frame()

	release(&r)
	rig_open(&r)
	it = one_button()
	ui.end_frame()
	testing.expect(t, it.clicked, "a press and release on the button clicks it")
}

@(test)
test_button_hover_variant_reaches_computed :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 5, 5)
	rig_open(&r)
	one_button({flags = {.No_Anim}})
	ui.end_frame()

	rig_open(&r)
	it := one_button({flags = {.No_Anim}})
	ui.end_frame()

	testing.expect(t, it.hovered, "the pointer is over the button")
	testing.expect_value(t, it.node.computed.bg.(ui.Color), ui.theme().accent_hover)
}

@(test)
test_button_activates_on_space_when_focused :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 5, 5)
	rig_open(&r)
	it := one_button()
	ui.end_frame()

	ui.set_focus(it.id)
	rig_open(&r)
	one_button()
	ui.end_frame()

	tap(&r, .Space)
	rig_open(&r)
	it = one_button()
	ui.end_frame()
	testing.expect(t, it.pressed, "space presses a focused button")
	testing.expect(t, !it.clicked, "the click waits for the key to come up")

	untap(&r, .Space)
	rig_open(&r)
	it = one_button()
	ui.end_frame()
	testing.expect(t, it.clicked, "releasing space completes the click")
}

@(test)
test_disabled_button_never_clicks :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 5, 5)
	rig_open(&r)
	one_button({flags = {.Disabled}})
	ui.end_frame()

	press(&r)
	rig_open(&r)
	one_button({flags = {.Disabled}})
	ui.end_frame()

	release(&r)
	rig_open(&r)
	it := one_button({flags = {.Disabled}})
	ui.end_frame()

	testing.expect(t, !it.clicked, "a disabled button is not hit-testable")
	testing.expect(t, !it.hovered, "a disabled button does not hover")
}

// ---- image ----

@(test)
test_image_emits_a_textured_command :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	{
		ui.scope({key = "root", props = {w = ui.Px(100), h = ui.Px(100), dir = .Column}})
		ui.image(ui.Texture(7), {key = "img", props = {pad = ui.all(5)}})
	}
	list := ui.end_frame()

	found := false
	for cmd in list.cmds {
		if v, ok := cmd.(ui.Cmd_Image); ok {
			found = true
			testing.expect_value(t, v.tex, ui.Texture(7))
			testing.expect_value(t, v.rect, ui.Rect{5, 5, 90, 90})
		}
	}
	testing.expect(t, found, "image emits a Cmd_Image at the padding box")
}

// ---- checkbox and radio ----

one_checkbox :: proc(value: ^bool) -> ui.Interaction {
	ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
	return ui.checkbox("On", value, {key = "cb"})
}

@(test)
test_checkbox_toggles_and_checks_the_same_frame :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	value := false
	r: Rig
	move(&r, 5, 8)
	rig_open(&r)
	one_checkbox(&value)
	ui.end_frame()

	press(&r)
	rig_open(&r)
	one_checkbox(&value)
	ui.end_frame()

	release(&r)
	rig_open(&r)
	it := one_checkbox(&value)
	ui.end_frame()

	testing.expect(t, value, "the click flipped the caller's bool")
	testing.expect(t, it.changed, "changed fires on the flip frame")
	testing.expect(t, .Checked in it.node.state, ".Checked lands the same frame as the click")

	rig_open(&r)
	it = one_checkbox(&value)
	ui.end_frame()
	testing.expect(t, !it.changed, "changed is a one-frame edge")
	testing.expect(t, .Checked in it.node.state, ".Checked is re-derived from the value each frame")
}

@(test)
test_checkbox_box_uses_the_accent_when_checked :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	value := true
	r: Rig
	move(&r, 700, 500)
	rig_open(&r)
	it := one_checkbox(&value)
	ui.end_frame()

	rig_open(&r)
	it = one_checkbox(&value)
	ui.end_frame()

	box := ui.find(ui.hash_string(it.id, "box"))
	testing.expect(t, box != nil, "the checkbox has a box sub-node")
	testing.expect_value(t, box.computed.bg.(ui.Color), ui.theme().accent)
	testing.expect_value(t, box.rect.w, f32(16))
}

Tab :: enum u8 {
	Songs,
	Albums,
}

radio_pair :: proc(value: ^Tab) -> Pair {
	ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
	out: Pair
	out.a = ui.radio("Songs", value, Tab.Songs, {key = "ra"})
	out.b = ui.radio("Albums", value, Tab.Albums, {key = "rb"})
	return out
}

@(test)
test_radio_writes_the_option_and_only_the_winner_changes :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	value := Tab.Songs
	r: Rig
	move(&r, 5, 24)
	rig_open(&r)
	radio_pair(&value)
	ui.end_frame()

	press(&r)
	rig_open(&r)
	radio_pair(&value)
	ui.end_frame()

	release(&r)
	rig_open(&r)
	p := radio_pair(&value)
	ui.end_frame()

	testing.expect_value(t, value, Tab.Albums)
	testing.expect(t, p.b.changed, "the radio that took the value reports changed")
	testing.expect(t, !p.a.changed, "the radio that lost the value does not")
	testing.expect(t, .Checked in p.b.node.state, "the winner is checked the same frame")

	rig_open(&r)
	p = radio_pair(&value)
	ui.end_frame()
	testing.expect(t, .Checked in p.b.node.state, "the winner stays checked")
	testing.expect(t, .Checked not_in p.a.node.state, "the loser clears on the next frame")
	testing.expect(t, !p.b.changed, "changed is a one-frame edge")
}

// ---- slider ----

SLIDER_W :: f32(200)
SLIDER_TRAVEL :: SLIDER_W - 14

one_slider :: proc(value: ^f32) -> ui.Interaction {
	ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
	return ui.slider(value, 0, 1, {key = "sl", props = {w = ui.Px(SLIDER_W)}})
}

slider_x :: proc(frac: f32) -> f32 {
	return frac * SLIDER_TRAVEL + 7
}

@(test)
test_slider_press_maps_the_pointer_to_the_value :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	value := f32(0)
	r: Rig
	move(&r, 700, 500)
	rig_open(&r)
	one_slider(&value)
	ui.end_frame()

	move(&r, slider_x(0.25), 10)
	press(&r)
	rig_open(&r)
	it := one_slider(&value)
	ui.end_frame()

	testing.expect(t, near(value, 0.25), "press maps x to the value")
	testing.expect(t, it.changed, "the write reports changed")
}

@(test)
test_slider_keeps_tracking_outside_its_rect :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	value := f32(0.5)
	r: Rig
	move(&r, slider_x(0.5), 10)
	rig_open(&r)
	one_slider(&value)
	ui.end_frame()

	press(&r)
	rig_open(&r)
	one_slider(&value)
	ui.end_frame()

	move(&r, -400, 400)
	rig_open(&r)
	it := one_slider(&value)
	ui.end_frame()
	testing.expect_value(t, value, f32(0))
	testing.expect(t, ui.wants_mouse(), "the slider captured the mouse")
	testing.expect(t, ui.hovered() == it.node, "capture keeps the slider hovered off-rect")

	move(&r, 4000, 400)
	rig_open(&r)
	one_slider(&value)
	ui.end_frame()
	testing.expect_value(t, value, f32(1))

	release(&r)
	rig_open(&r)
	one_slider(&value)
	ui.end_frame()

	move(&r, 700, 500)
	rig_open(&r)
	one_slider(&value)
	ui.end_frame()
	testing.expect(t, ui.hovered() == nil, "the capture was released on mouse up")
}

@(test)
test_slider_thumb_rides_the_grow_weights :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	value := f32(0.5)
	it: ui.Interaction
	open_frame()
	{
		it = one_slider(&value)
	}
	ui.end_frame()

	open_frame()
	{
		it = one_slider(&value)
	}
	ui.end_frame()

	thumb := ui.find(ui.hash_string(it.id, "thumb"))
	testing.expect(t, thumb != nil, "the slider has a thumb")
	testing.expect(t, near(thumb.rect.x, 0.5 * SLIDER_TRAVEL), "the thumb sits at t * travel")
	testing.expect_value(t, thumb.rect.w, f32(14))
}

@(test)
test_slider_steps_with_the_keyboard :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	value := f32(0.5)
	r: Rig
	move(&r, 700, 500)
	rig_open(&r)
	it := one_slider(&value)
	ui.end_frame()

	ui.set_focus(it.id)
	rig_open(&r)
	one_slider(&value)
	ui.end_frame()

	tap(&r, .Right)
	rig_open(&r)
	one_slider(&value)
	ui.end_frame()
	untap(&r, .Right)
	testing.expect(t, near(value, 0.51), "right steps by 1%")

	mods_set(&r, .Shift)
	tap(&r, .Right)
	rig_open(&r)
	one_slider(&value)
	ui.end_frame()
	untap(&r, .Right)
	mods_clear(&r)
	testing.expect(t, near(value, 0.511), "shift makes the step fine")

	tap(&r, .Page_Up)
	rig_open(&r)
	one_slider(&value)
	ui.end_frame()
	untap(&r, .Page_Up)
	testing.expect(t, near(value, 0.611), "page up steps by 10%")

	tap(&r, .Home)
	rig_open(&r)
	one_slider(&value)
	ui.end_frame()
	untap(&r, .Home)
	testing.expect_value(t, value, f32(0))
}

@(test)
test_slider_ignores_space :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	value := f32(0.5)
	r: Rig
	move(&r, 700, 500)
	rig_open(&r)
	it := one_slider(&value)
	ui.end_frame()

	ui.set_focus(it.id)
	rig_open(&r)
	one_slider(&value)
	ui.end_frame()

	tap(&r, .Space)
	rig_open(&r)
	one_slider(&value)
	ui.end_frame()
	untap(&r, .Space)

	rig_open(&r)
	one_slider(&value)
	ui.end_frame()

	testing.expect_value(t, value, f32(0.5))
}

// ---- Position.Relative ----

@(test)
test_relative_parent_anchors_its_absolute_child :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	child: ui.Interaction
	open_frame()
	{
		ui.scope({key = "root", props = {w = ui.Px(400), h = ui.Px(300), dir = .Column}})
		ui.leaf({key = "pad", props = {w = ui.STRETCH, h = ui.Px(50)}})
		{
			ui.scope(
				{
					key = "rel",
					props = {w = ui.Px(200), h = ui.Px(100), position = .Relative},
				},
			)
			child = ui.leaf(
				{
					key = "abs",
					props = {
						position = .Absolute,
						inset = {l = 10, t = 20},
						w = ui.Px(30),
						h = ui.Px(30),
					},
				},
			)
		}
	}
	ui.end_frame()

	expect_rect(t, child.node, 10, 70, 30, 30)
}

@(test)
test_relative_still_participates_in_flow :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	rel, after: ui.Interaction
	open_frame()
	{
		ui.scope({key = "root", props = {w = ui.Px(400), h = ui.Px(300), dir = .Column}})
		rel = ui.leaf(
			{key = "rel", props = {w = ui.Px(200), h = ui.Px(40), position = .Relative}},
		)
		after = ui.leaf({key = "after", props = {w = ui.Px(200), h = ui.Px(40)}})
	}
	ui.end_frame()

	expect_rect(t, rel.node, 0, 0, 200, 40)
	expect_rect(t, after.node, 0, 40, 200, 40)
}
