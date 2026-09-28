package tests

import "core:strings"
import "core:testing"
import ui "../loom"

// A hidden panel is closed, so without a remembered slot it comes back wherever
// dock_insert_default puts it — beside the largest tab set, not where it was.

// Declares A in the root and B in a right-hand split, B behind `open`.
@(private = "file")
home_frame :: proc(open: ^bool) -> ui.Dock_Id {
	d := ui.dockspace(DOCK_ID, {}, {props = {w = ui.Px(DOCK_W), h = ui.Px(DOCK_H)}})
	if ui.panel(d, "A") {
		ui.end_panel()
	}
	if ui.panel(d, "B", open) {
		ui.end_panel()
	}
	return d
}

@(private = "file")
home_frames :: proc(r: ^Rig, open: ^bool, count: int) -> ui.Dock_Id {
	d: ui.Dock_Id
	for _ in 0 ..< count {
		rig_open(r)
		d = home_frame(open)
		ui.end_frame()
	}
	return d
}

@(test)
test_dock_hidden_panel_returns_to_its_own_slot :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	open := true
	d := home_frames(&r, &open, 3)

	rig_open(&r)
	_, right := ui.dock_split(d, "", .Right, 0.4)
	ui.dock_panel(d, "B", right)
	ui.end_frame()
	home_frames(&r, &open, 3)

	sp := dock_space_of(&ctx)
	testing.expect_value(t, sp.root.kind, ui.Dock_Kind.Split)
	ratio := sp.root.ratio

	open = false
	home_frames(&r, &open, 3)
	testing.expect_value(t, sp.root.kind, ui.Dock_Kind.Tabs)

	open = true
	home_frames(&r, &open, 3)

	testing.expect_value(t, sp.root.kind, ui.Dock_Kind.Split)
	testing.expect_value(t, len(sp.root.children[0].tabs), 1)
	testing.expect_value(t, sp.root.children[0].tabs[0].title, "A")
	testing.expect_value(t, len(sp.root.children[1].tabs), 1)
	testing.expect_value(t, sp.root.children[1].tabs[0].title, "B")
	testing.expect(t, near(sp.root.ratio, ratio), "and on the same side at the same ratio")
}

@(test)
test_dock_hidden_panel_returns_to_a_shared_node :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	open := true
	home_frames(&r, &open, 3)

	sp := dock_space_of(&ctx)
	testing.expect_value(t, len(sp.root.tabs), 2)

	open = false
	home_frames(&r, &open, 3)
	testing.expect_value(t, len(sp.root.tabs), 1)

	open = true
	home_frames(&r, &open, 3)

	testing.expect_value(t, sp.root.kind, ui.Dock_Kind.Tabs)
	testing.expect_value(t, len(sp.root.tabs), 2)
	testing.expect_value(t, sp.root.tabs[1].title, "B")
	testing.expect_value(t, sp.root.active, 1)
}

@(test)
test_dock_restored_panel_is_the_active_tab :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	open := true
	home_frames(&r, &open, 3)

	sp := dock_space_of(&ctx)
	sp.root.active = 0

	open = false
	home_frames(&r, &open, 3)
	open = true

	rig_open(&r)
	shown := false
	d := ui.dockspace(DOCK_ID, {}, {props = {w = ui.Px(DOCK_W), h = ui.Px(DOCK_H)}})
	if ui.panel(d, "A") {
		ui.end_panel()
	}
	if ui.panel(d, "B", &open) {
		shown = true
		ui.end_panel()
	}
	ui.end_frame()

	testing.expect(t, shown, "the panel it re-opens is the one the frame builds")
	testing.expect_value(t, sp.root.active, 1)
}

@(test)
test_dock_focus_raises_a_tab :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	d := dock_frames(&r, {"A", "B"}, 3)

	sp := dock_space_of(&ctx)
	sp.root.active = 0

	rig_open(&r)
	ok := ui.dock_focus(d, "B")
	missing := ui.dock_focus(d, "Ghost")
	ui.end_frame()

	testing.expect(t, ok, "a listed tab is raised")
	testing.expect(t, !missing, "a title the space does not hold is not")
	testing.expect_value(t, sp.root.active, 1)

	rig_open(&r)
	built := false
	dd := ui.dockspace(DOCK_ID, {}, {props = {w = ui.Px(DOCK_W), h = ui.Px(DOCK_H)}})
	if ui.panel(dd, "A") {
		ui.end_panel()
	}
	if ui.panel(dd, "B") {
		built = true
		ui.end_panel()
	}
	ui.end_frame()
	testing.expect(t, built, "and the raised panel builds its body")
}

@(test)
test_dock_home_rides_the_save :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	open := true
	d := home_frames(&r, &open, 3)

	rig_open(&r)
	_, right := ui.dock_split(d, "", .Right, 0.4)
	ui.dock_panel(d, "B", right)
	ui.end_frame()
	home_frames(&r, &open, 3)

	open = false
	home_frames(&r, &open, 3)

	rig_open(&r)
	b := strings.builder_make(context.temp_allocator)
	ui.dock_save(d, strings.to_writer(&b))
	text := strings.to_string(b)
	ui.end_frame()

	testing.expect(t, strings.contains(text, "home.B = right"), "the parked slot is written")
	testing.expect(t, strings.contains(text, " A"), "named by the tab it sat beside")

	rig_open(&r)
	loaded := ui.dock_load(d, transmute([]byte)text)
	ui.end_frame()
	testing.expect(t, loaded, "the file reloads")

	open = true
	home_frames(&r, &open, 3)

	sp := dock_space_of(&ctx)
	testing.expect_value(t, sp.root.kind, ui.Dock_Kind.Split)
	testing.expect_value(t, len(sp.root.children[1].tabs), 1)
	testing.expect_value(t, sp.root.children[1].tabs[0].title, "B")
	testing.expect(t, near(sp.root.ratio, 0.6), "at the ratio it was saved with")
}
