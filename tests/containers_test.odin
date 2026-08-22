package tests

import "core:testing"
import ui "../loom"

SCROLL_W :: f32(200)
SCROLL_H :: f32(100)
ROW_H :: f32(50)

scroll_tree :: proc(rows: int) -> ui.Interaction {
	ui.scope({key = "root", props = {w = ui.Px(400), h = ui.Px(300), dir = .Column}})
	it := ui.scroll({key = "sc", props = {w = ui.Px(SCROLL_W), h = ui.Px(SCROLL_H)}})
	for i in 0 ..< rows {
		ui.push_id_int(i64(i))
		ui.leaf({key = "row", props = {w = ui.STRETCH, h = ui.Px(ROW_H)}})
		ui.pop_id()
	}
	ui.end()
	return it
}

bars_of :: proc(sc: ui.Id) -> ^ui.Node {
	return ui.find(ui.hash_string(sc, "loom.bars"))
}

vbar_of :: proc(sc: ui.Id) -> ^ui.Node {
	bars := ui.hash_string(sc, "loom.bars")
	return ui.find(ui.hash_string(ui.hash_string(bars, "vrow"), "vbar"))
}

vthumb_of :: proc(sc: ui.Id) -> ^ui.Node {
	bars := ui.hash_string(sc, "loom.bars")
	vbar := ui.hash_string(ui.hash_string(bars, "vrow"), "vbar")
	return ui.find(ui.hash_string(vbar, "vthumb"))
}

// ---- scroll ----

@(test)
test_scroll_has_no_bars_when_content_fits :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	it: ui.Interaction
	for _ in 0 ..< 3 {
		open_frame()
		it = scroll_tree(1)
		ui.end_frame()
	}

	testing.expect(t, bars_of(it.id) == nil, "no overflow means no scrollbar overlay")
}

@(test)
test_scroll_bars_appear_the_frame_after_overflow :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	it := scroll_tree(4)
	ui.end_frame()
	testing.expect(t, bars_of(it.id) == nil, "the first frame has no geometry yet")

	open_frame()
	it = scroll_tree(4)
	ui.end_frame()
	testing.expect(t, bars_of(it.id) != nil, "the bars land once content is known")

	testing.expect_value(t, it.node.content.y, 4 * ROW_H)
	testing.expect_value(t, ui.scroll_max(it.node).y, 4 * ROW_H - SCROLL_H)
}

@(test)
test_scroll_thumb_is_sized_by_box_over_content :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	it: ui.Interaction
	for _ in 0 ..< 3 {
		open_frame()
		it = scroll_tree(4)
		ui.end_frame()
	}

	th := vthumb_of(it.id)
	testing.expect(t, th != nil, "the vertical thumb exists")
	testing.expect(t, near(th.rect.h, 48), "thumb is box/content of the padded bar")
	testing.expect(t, near(th.rect.y, 2), "at scroll 0 the thumb sits at the top")
	testing.expect_value(t, th.computed.bg.(ui.Color), ui.theme().scrollbar)
}

@(test)
test_scroll_overlay_does_not_steal_hover :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 40, 40)
	it: ui.Interaction
	for _ in 0 ..< 3 {
		rig_open(&r)
		it = scroll_tree(4)
		ui.end_frame()
	}

	bars := bars_of(it.id)
	testing.expect(t, bars != nil, "the overlay is present")
	testing.expect(t, ui.hovered() != bars, "the pass-through overlay never hovers")
}

@(test)
test_scroll_thumb_drag_maps_to_the_offset :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	it: ui.Interaction
	move(&r, 195, 10)
	for _ in 0 ..< 3 {
		rig_open(&r)
		it = scroll_tree(4)
		ui.end_frame()
	}

	th := vthumb_of(it.id)
	testing.expect(t, th != nil, "the thumb exists")
	testing.expect(t, ui.hovered() == th, "the pointer is over the thumb")

	press(&r)
	rig_open(&r)
	it = scroll_tree(4)
	ui.end_frame()
	testing.expect_value(t, it.node.scroll.y, f32(0))

	move(&r, 195, 10 + 3)
	rig_open(&r)
	it = scroll_tree(4)
	ui.end_frame()
	testing.expect_value(t, it.node.scroll.y, f32(0))

	move(&r, 195, 10 + 24)
	rig_open(&r)
	it = scroll_tree(4)
	ui.end_frame()
	testing.expect(
		t,
		near(it.node.scroll.y, 24.0 / 48.0 * 100.0),
		"the drag maps absolutely, with no DRAG_SLOP jump",
	)

	move(&r, 195, 10 + 400)
	rig_open(&r)
	it = scroll_tree(4)
	ui.end_frame()
	testing.expect_value(t, it.node.scroll.y, ui.scroll_max(it.node).y)

	move(&r, 195, 10 - 400)
	rig_open(&r)
	it = scroll_tree(4)
	ui.end_frame()
	testing.expect_value(t, it.node.scroll.y, f32(0))
}

@(test)
test_scroll_wheel_still_routes_with_bars_present :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 40, 40)
	it: ui.Interaction
	for _ in 0 ..< 3 {
		rig_open(&r)
		it = scroll_tree(4)
		ui.end_frame()
	}

	spin(&r, 0, 1)
	rig_open(&r)
	it = scroll_tree(4)
	ui.end_frame()

	testing.expect(t, it.node.scroll_want.y > 0, "the wheel still reaches the scroll node")
}

// ---- popup ----

popup_tree :: proc(open: ^bool, top_pad: f32 = 0) -> ui.Interaction {
	ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
	if top_pad > 0 {
		ui.leaf({key = "pad", props = {w = ui.STRETCH, h = ui.Px(top_pad)}})
	}
	a := ui.button("menu", {key = "anchor"})
	if ui.popup(open, a.id, {key = "pop", props = {w = ui.Px(120), h = ui.Px(80)}}) {
		defer ui.end()
		ui.leaf({key = "item", props = {w = ui.STRETCH, h = ui.Px(20)}})
	}
	return a
}

@(test)
test_popup_opens_below_its_anchor :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	open := true
	r: Rig
	move(&r, 700, 500)

	a: ui.Interaction
	for _ in 0 ..< 3 {
		rig_open(&r)
		a = popup_tree(&open)
		ui.end_frame()
	}

	pop := ui.find(ui.hash_string(tree_root(), "pop"))
	testing.expect(t, pop != nil, "the popup node exists while open")
	testing.expect(t, near(pop.rect.y, a.node.rect.y + a.node.rect.h + 4), "it sits below the anchor")
	testing.expect(t, near(pop.rect.x, a.node.rect.x), "left-aligned with the anchor")
	testing.expect(t, .Open in pop.state, "an open popup carries .Open")
}

@(test)
test_popup_is_invisible_on_its_first_frame :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	open := true
	r: Rig
	move(&r, 700, 500)

	rig_open(&r)
	popup_tree(&open)
	ui.end_frame()

	pop := ui.find(ui.hash_string(tree_root(), "pop"))
	testing.expect(t, pop != nil, "the node exists")
	testing.expect_value(t, pop.computed.opacity.(f32), f32(0))

	for _ in 0 ..< 12 {
		rig_open(&r)
		popup_tree(&open)
		ui.end_frame()
	}
	testing.expect_value(t, pop.computed.opacity.(f32), f32(1))
}

@(test)
test_popup_flips_above_near_the_bottom :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	open := true
	r: Rig
	move(&r, 700, 100)

	a: ui.Interaction
	for _ in 0 ..< 3 {
		rig_open(&r)
		a = popup_tree(&open, 560)
		ui.end_frame()
	}

	pop := ui.find(ui.hash_string(tree_root(), "pop"))
	testing.expect(t, pop != nil, "the popup exists")
	testing.expect(t, pop.rect.y < a.node.rect.y, "it flipped above the anchor")
	testing.expect(t, near(pop.rect.y + pop.rect.h + 4, a.node.rect.y), "gap preserved above")
}

@(test)
test_popup_closes_on_an_outside_press :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	open := true
	r: Rig
	move(&r, 700, 500)
	for _ in 0 ..< 3 {
		rig_open(&r)
		popup_tree(&open)
		ui.end_frame()
	}
	testing.expect(t, open, "still open before the press")

	press(&r)
	rig_open(&r)
	popup_tree(&open)
	ui.end_frame()
	testing.expect(t, !open, "a press outside closed it")
}

@(test)
test_popup_survives_a_press_inside :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	open := true
	r: Rig
	move(&r, 700, 500)
	for _ in 0 ..< 3 {
		rig_open(&r)
		popup_tree(&open)
		ui.end_frame()
	}

	pop := ui.find(ui.hash_string(tree_root(), "pop"))
	move(&r, pop.rect.x + 10, pop.rect.y + 10)
	rig_open(&r)
	popup_tree(&open)
	ui.end_frame()

	press(&r)
	rig_open(&r)
	popup_tree(&open)
	ui.end_frame()
	testing.expect(t, open, "a press inside the popup keeps it open")
}

@(test)
test_popup_closes_on_escape_and_consumes_the_key :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	open := true
	r: Rig
	move(&r, 700, 500)
	for _ in 0 ..< 3 {
		rig_open(&r)
		popup_tree(&open)
		ui.end_frame()
	}

	tap(&r, .Escape)
	rig_open(&r)
	popup_tree(&open)
	consumed := !ui.key_pressed(.Escape)
	ui.end_frame()
	untap(&r, .Escape)

	testing.expect(t, !open, "escape closed the popup")
	testing.expect(t, consumed, "escape was consumed so an outer popup survives")
}

@(test)
test_closed_popup_leaves_the_tree_balanced :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	open := false
	r: Rig
	move(&r, 700, 500)
	for _ in 0 ..< 3 {
		rig_open(&r)
		popup_tree(&open)
		ui.end_frame()
	}

	pop := ui.find(ui.hash_string(tree_root(), "pop"))
	testing.expect(t, pop == nil, "a closed popup emits no node at all")
}

// ---- tooltip ----

tip_tree :: proc(text: string) -> ui.Interaction {
	ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
	a := ui.button("hover me", {key = "anchor"})
	ui.tooltip(text, a.id, 0.5, {key = "tip"})
	return a
}

find_tip :: proc(anchor: ui.Id) -> ^ui.Node {
	root := tree_root()
	return ui.find(ui.hash_string(ui.hash_int(root, i64(anchor)), "tip"))
}

@(test)
test_tooltip_waits_for_the_delay :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 5, 5)
	a: ui.Interaction
	for _ in 0 ..< 2 {
		rig_open(&r)
		a = tip_tree("hi")
		ui.end_frame()
	}
	testing.expect(t, find_tip(a.id) == nil, "nothing before the delay")
	testing.expect(t, ui.animating(), "the hover timer keeps the host redrawing")

	rig_open(&r, 0.6)
	a = tip_tree("hi")
	ui.end_frame()

	tip := find_tip(a.id)
	testing.expect(t, tip != nil, "the tooltip fires after the delay")
	testing.expect(t, .Pass_Through in tip.flags, "it never hit-tests")
	testing.expect(t, ui.hovered() == a.node, "the anchor keeps its hover")
}

@(test)
test_tooltip_resets_when_the_pointer_leaves :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 5, 5)
	a: ui.Interaction
	for _ in 0 ..< 2 {
		rig_open(&r)
		a = tip_tree("hi")
		ui.end_frame()
	}

	move(&r, 700, 500)
	rig_open(&r, 0.6)
	a = tip_tree("hi")
	ui.end_frame()
	testing.expect(t, find_tip(a.id) == nil, "moving off resets the timer")

	move(&r, 5, 5)
	rig_open(&r, 0.4)
	a = tip_tree("hi")
	ui.end_frame()
	testing.expect(t, find_tip(a.id) == nil, "the timer restarted from zero")
}

@(test)
test_tooltip_is_cancelled_by_a_mouse_down :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	move(&r, 5, 5)
	a: ui.Interaction
	for _ in 0 ..< 2 {
		rig_open(&r)
		a = tip_tree("hi")
		ui.end_frame()
	}

	press(&r)
	rig_open(&r, 0.6)
	a = tip_tree("hi")
	ui.end_frame()
	testing.expect(t, find_tip(a.id) == nil, "a held button suppresses the tooltip")
}

@(test)
test_two_tooltips_on_one_source_line_do_not_collide :: proc(t: ^testing.T) {
	ctx: ui.Context
	wired(&ctx)
	defer ui.destroy(&ctx)

	build :: proc() -> Pair {
		ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Row}})
		out: Pair
		out.a = ui.leaf(
			{key = "a", flags = {.Clickable}, props = {w = ui.Px(100), h = ui.Px(100)}},
		)
		out.b = ui.leaf(
			{key = "b", flags = {.Clickable}, props = {w = ui.Px(100), h = ui.Px(100)}},
		)
		for id in ([2]ui.Id{out.a.id, out.b.id}) {
			ui.tooltip("tip", id, 0.5)
		}
		return out
	}

	r: Rig
	move(&r, 5, 5)
	for _ in 0 ..< 2 {
		rig_open(&r)
		build()
		ui.end_frame()
	}

	rig_open(&r, 0.6)
	build()
	ui.end_frame()
}

tree_root :: proc() -> ui.Id {
	return ui.hash_string(ui.hash_string(0, "loom.root"), "root")
}
