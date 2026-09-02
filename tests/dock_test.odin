package tests

import "core:strings"
import "core:testing"
import ui "../loom"

DOCK_W :: f32(400)
DOCK_H :: f32(300)
DOCK_ID :: "main"

Fake_Vp :: struct {
	measures:  int,
	created:   int,
	destroyed: int,
	next:      u64,
	ev:        ui.Viewport_Events,
}

fake_viewport_backend :: proc(f: ^Fake_Vp) -> ui.Backend {
	b := fake_backend()
	b.user = f
	b.viewports = ui.Viewport_Ops {
		create = proc(title: string, rect: ui.Rect, user: rawptr) -> ui.Viewport_Handle {
			g := (^Fake_Vp)(user)
			g.created += 1
			g.next += 1
			return ui.Viewport_Handle(g.next)
		},
		destroy = proc(v: ui.Viewport_Handle, user: rawptr) {
			g := (^Fake_Vp)(user)
			g.destroyed += 1
		},
		set_rect = proc(v: ui.Viewport_Handle, rect: ui.Rect, user: rawptr) {},
		begin = proc(v: ui.Viewport_Handle, user: rawptr) {},
		end = proc(v: ui.Viewport_Handle, user: rawptr) {},
		poll = proc(v: ui.Viewport_Handle, user: rawptr) -> ui.Viewport_Events {
			return (^Fake_Vp)(user).ev
		},
	}
	return b
}

dock_space_of :: proc(ctx: ^ui.Context) -> ^ui.Dock_Space {
	return ctx.docks[DOCK_ID]
}

dock_frame :: proc(titles: []string, cfg: ui.Dock_Config = {}) -> ui.Dock_Id {
	d := ui.dockspace(DOCK_ID, cfg, {props = {w = ui.Px(DOCK_W), h = ui.Px(DOCK_H)}})
	for title in titles {
		if ui.panel(d, title) {
			ui.leaf({key = "body", props = {w = ui.STRETCH, h = ui.Px(20)}})
			ui.end_panel()
		}
	}
	return d
}

dock_frames :: proc(r: ^Rig, titles: []string, count: int, cfg: ui.Dock_Config = {}) -> ui.Dock_Id {
	d: ui.Dock_Id
	for _ in 0 ..< count {
		rig_open(r)
		d = dock_frame(titles, cfg)
		ui.end_frame()
	}
	return d
}

dock_tab_node :: proc(sp: ^ui.Dock_Space, dn: ^ui.Dock_Node, title: string) -> ^ui.Node {
	seed := ui.hash_int(sp.node.id, i64(dn.id))
	bar := ui.hash_string(seed, "loom.dockbar")
	return ui.find(ui.hash_string(bar, title))
}

dock_splitter_node :: proc(sp: ^ui.Dock_Space, dn: ^ui.Dock_Node) -> ^ui.Node {
	seed := ui.hash_int(sp.node.id, i64(dn.id))
	return ui.find(ui.hash_string(seed, "loom.docksplit"))
}

dock_center :: proc(r: ui.Rect) -> ui.Vec2 {
	return {r.x + r.w * 0.5, r.y + r.h * 0.5}
}

dock_drag_to :: proc(r: ^Rig, titles: []string, from, to: ui.Vec2, cfg: ui.Dock_Config = {}) {
	move(r, from.x, from.y)
	press(r)
	rig_open(r)
	dock_frame(titles, cfg)
	ui.end_frame()

	move(r, to.x, to.y)
	rig_open(r)
	dock_frame(titles, cfg)
	ui.end_frame()

	release(r)
	rig_open(r)
	dock_frame(titles, cfg)
	ui.end_frame()

	rig_open(r)
	dock_frame(titles, cfg)
	ui.end_frame()
}

// ---- tree ----

@(test)
test_dock_unknown_panels_land_in_one_tab_set :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	dock_frames(&r, {"A", "B", "C"}, 3)

	sp := dock_space_of(&ctx)
	testing.expect(t, sp != nil, "the dockspace must be retained by id")
	testing.expect_value(t, sp.root.kind, ui.Dock_Kind.Tabs)
	testing.expect_value(t, len(sp.root.tabs), 3)
	testing.expect_value(t, sp.root.active, 0)
}

@(test)
test_dock_only_the_active_tab_opens_a_panel :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	dock_frames(&r, {"A", "B"}, 3)

	rig_open(&r)
	d := ui.dockspace(DOCK_ID, {}, {props = {w = ui.Px(DOCK_W), h = ui.Px(DOCK_H)}})
	a := ui.panel(d, "A")
	if a {
		ui.end_panel()
	}
	b := ui.panel(d, "B")
	if b {
		ui.end_panel()
	}
	ui.end_frame()

	testing.expect(t, a, "the active tab opens its panel")
	testing.expect(t, !b, "an inactive tab must report closed and skip end_panel")
}

@(test)
test_dock_split_resolves_two_halves :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	d := dock_frames(&r, {"A"}, 3)

	rig_open(&r)
	_, right := ui.dock_split(d, "", .Right, 0.5)
	ui.dock_panel(d, "B", right)
	dock_frame({"A", "B"})
	ui.end_frame()

	dock_frames(&r, {"A", "B"}, 2)

	sp := dock_space_of(&ctx)
	testing.expect_value(t, sp.root.kind, ui.Dock_Kind.Split)
	testing.expect_value(t, sp.root.dir, ui.Direction.Row)

	half := (DOCK_W - ui.DOCK_SPLITTER) * 0.5
	l := sp.root.children[0].rect
	rr := sp.root.children[1].rect
	testing.expect(t, near(l.w, half) && near(l.x, 0), "the first child takes the left half")
	testing.expect(
		t,
		near(rr.w, half) && near(rr.x, half + ui.DOCK_SPLITTER),
		"the second child starts after the splitter",
	)
	testing.expect(t, near(l.h, DOCK_H) && near(rr.h, DOCK_H), "a row split keeps full height")
}

@(test)
test_dock_closed_panel_drops_its_tab :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	open_a := true
	open_b := true

	for i in 0 ..< 4 {
		rig_open(&r)
		d := ui.dockspace(DOCK_ID, {}, {props = {w = ui.Px(DOCK_W), h = ui.Px(DOCK_H)}})
		if ui.panel(d, "A", &open_a) {
			ui.end_panel()
		}
		if ui.panel(d, "B", &open_b) {
			ui.end_panel()
		}
		ui.end_frame()
		if i == 2 {
			open_b = false
		}
	}

	sp := dock_space_of(&ctx)
	testing.expect_value(t, len(sp.root.tabs), 1)
	testing.expect_value(t, sp.root.tabs[0].title, "A")
}

@(test)
test_dock_closing_the_last_tab_collapses_the_split :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	open_b := true
	d := dock_frames(&r, {"A"}, 3)

	rig_open(&r)
	_, right := ui.dock_split(d, "", .Right, 0.5)
	ui.dock_panel(d, "B", right)
	ui.end_frame()

	sp := dock_space_of(&ctx)
	testing.expect_value(t, sp.root.kind, ui.Dock_Kind.Split)

	for i in 0 ..< 4 {
		rig_open(&r)
		dd := ui.dockspace(DOCK_ID, {}, {props = {w = ui.Px(DOCK_W), h = ui.Px(DOCK_H)}})
		if ui.panel(dd, "A") {
			ui.end_panel()
		}
		if ui.panel(dd, "B", &open_b) {
			ui.end_panel()
		}
		ui.end_frame()
		if i == 1 {
			open_b = false
		}
	}

	testing.expect_value(t, sp.root.kind, ui.Dock_Kind.Tabs)
	testing.expect_value(t, len(sp.root.tabs), 1)
	testing.expect_value(t, sp.root.tabs[0].title, "A")
	testing.expect(t, sp.root.parent == nil, "the lifted sibling becomes the root")
}

// ---- chrome ----

@(test)
test_dock_splitter_drag_moves_the_ratio :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	d := dock_frames(&r, {"A"}, 3)

	rig_open(&r)
	_, right := ui.dock_split(d, "", .Right, 0.5)
	ui.dock_panel(d, "B", right)
	ui.end_frame()
	dock_frames(&r, {"A", "B"}, 3)

	sp := dock_space_of(&ctx)
	sn := dock_splitter_node(sp, sp.root)
	testing.expect(t, sn != nil, "a split emits a splitter node")

	c := dock_center(sn.rect)
	move(&r, c.x, c.y)
	press(&r)
	dock_frames(&r, {"A", "B"}, 1)
	move(&r, c.x + 60, c.y)
	dock_frames(&r, {"A", "B"}, 2)
	release(&r)
	dock_frames(&r, {"A", "B"}, 1)

	testing.expect(t, sp.root.ratio > 0.6, "dragging right grows the first child")

	// The release must give the pointer back. A capture that stays sends each
	// later hit to the splitter, thus no other widget answers the mouse.
	testing.expect_value(t, ctx.capture_id, ui.Id(0))
	testing.expect_value(t, ctx.drag_id, ui.Id(0))
	testing.expect(t, !ctx.drag_active, "the drag stops at the release")
}

@(test)
test_dock_splitter_drag_clamps_to_min_panel :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	cfg := ui.Dock_Config {
		min_panel = {100, 100},
	}
	d := dock_frames(&r, {"A"}, 3, cfg)

	rig_open(&r)
	_, right := ui.dock_split(d, "", .Right, 0.5)
	ui.dock_panel(d, "B", right)
	ui.end_frame()
	dock_frames(&r, {"A", "B"}, 3, cfg)

	sp := dock_space_of(&ctx)
	sn := dock_splitter_node(sp, sp.root)
	c := dock_center(sn.rect)

	move(&r, c.x, c.y)
	press(&r)
	dock_frames(&r, {"A", "B"}, 1, cfg)
	move(&r, c.x + 900, c.y)
	dock_frames(&r, {"A", "B"}, 2, cfg)
	release(&r)
	dock_frames(&r, {"A", "B"}, 1, cfg)

	avail := DOCK_W - ui.DOCK_SPLITTER
	testing.expect(
		t,
		sp.root.children[1].rect.w >= 100 - 0.5,
		"the trailing child never shrinks past min_panel",
	)
	testing.expect(t, sp.root.ratio <= 1 - 100 / avail + 0.01, "the ratio is clamped, not the rect")

	// The release must give the pointer back. A capture that stays sends each
	// later hit to the splitter, thus no other widget answers the mouse.
	testing.expect_value(t, ctx.capture_id, ui.Id(0))
	testing.expect_value(t, ctx.drag_id, ui.Id(0))
	testing.expect(t, !ctx.drag_active, "the drag stops at the release")
}

// ---- drag to dock ----

@(test)
test_dock_drag_tab_to_edge_splits :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	dock_frames(&r, {"A", "B"}, 3)

	sp := dock_space_of(&ctx)
	tab := dock_tab_node(sp, sp.root, "B")
	testing.expect(t, tab != nil, "each visible tab emits a node")

	body := ui.Rect{0, ui.DOCK_TAB_H, DOCK_W, DOCK_H - ui.DOCK_TAB_H}
	target := ui.Vec2{body.x + body.w - 10, body.y + body.h * 0.5}
	dock_drag_to(&r, {"A", "B"}, dock_center(tab.rect), target)

	testing.expect_value(t, sp.root.kind, ui.Dock_Kind.Split)
	testing.expect_value(t, sp.root.dir, ui.Direction.Row)
	testing.expect_value(t, len(sp.root.children[0].tabs), 1)
	testing.expect_value(t, len(sp.root.children[1].tabs), 1)
	testing.expect_value(t, sp.root.children[1].tabs[0].title, "B")
}

@(test)
test_dock_drag_tab_to_center_merges :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	d := dock_frames(&r, {"A"}, 3)

	rig_open(&r)
	_, right := ui.dock_split(d, "", .Right, 0.5)
	ui.dock_panel(d, "B", right)
	ui.end_frame()
	dock_frames(&r, {"A", "B"}, 3)

	sp := dock_space_of(&ctx)
	left := sp.root.children[0]
	rgt := sp.root.children[1]
	tab := dock_tab_node(sp, rgt, "B")
	testing.expect(t, tab != nil, "the right tab set emits its tab")

	dock_drag_to(&r, {"A", "B"}, dock_center(tab.rect), dock_center(left.rect))

	testing.expect_value(t, sp.root.kind, ui.Dock_Kind.Tabs)
	testing.expect_value(t, len(sp.root.tabs), 2)
}

@(test)
test_dock_drag_across_two_dockspaces :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	for _ in 0 ..< 3 {
		rig_open(&r)
		two_docks()
		ui.end_frame()
	}

	main := ctx.docks["main"]
	side := ctx.docks["side"]
	tab := dock_tab_node(main, main.root, "A")
	testing.expect(t, tab != nil, "the source tab exists")

	to := dock_center(side.root.rect)
	c := dock_center(tab.rect)
	move(&r, c.x, c.y)
	press(&r)
	for i in 0 ..< 4 {
		if i == 1 {
			move(&r, to.x, to.y)
		}
		if i == 3 {
			release(&r)
		}
		rig_open(&r)
		two_docks()
		ui.end_frame()
	}
	rig_open(&r)
	two_docks()
	ui.end_frame()

	testing.expect_value(t, len(side.root.tabs), 2)
	testing.expect_value(t, len(main.root.tabs), 0)
}

two_docks :: proc() {
	a := ui.dockspace("main", {}, {props = {w = ui.Px(DOCK_W), h = ui.Px(DOCK_H)}})
	if ui.panel(a, "A") {
		ui.end_panel()
	}
	b := ui.dockspace("side", {}, {props = {w = ui.Px(DOCK_W), h = ui.Px(DOCK_H)}})
	if ui.panel(b, "S") {
		ui.end_panel()
	}
}

// ---- persistence ----

@(test)
test_dock_save_load_round_trip :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	d := dock_frames(&r, {"A"}, 3)

	rig_open(&r)
	_, right := ui.dock_split(d, "", .Right, 0.35)
	ui.dock_panel(d, "B", right)
	ui.end_frame()
	dock_frames(&r, {"A", "B"}, 3)

	sp := dock_space_of(&ctx)
	before := sp.root.children[0].rect
	ratio := sp.root.ratio

	rig_open(&r)
	b := strings.builder_make(context.temp_allocator)
	ui.dock_save(d, strings.to_writer(&b))
	text := strings.to_string(b)
	ui.end_frame()

	testing.expect(t, strings.contains(text, "[dock.main]"), "the section is named after the id")
	testing.expect(t, strings.contains(text, "tabs = A"), "tab titles are written")

	rig_open(&r)
	ok := ui.dock_load(d, transmute([]byte)text)
	ui.end_frame()
	testing.expect(t, ok, "a saved layout reloads")

	dock_frames(&r, {"A", "B"}, 3)

	testing.expect(t, near(sp.root.ratio, ratio), "the ratio survives the round trip")
	testing.expect(
		t,
		near(sp.root.children[0].rect.w, before.w),
		"the reloaded layout resolves to the same rects",
	)
}

@(test)
test_dock_load_skips_unknown_titles :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	d := dock_frames(&r, {"A"}, 3)

	text := `[dock.main]
root = n0
n0.kind = tabs
n0.tabs = A|Ghost
n0.active = 0
`

	rig_open(&r)
	ok := ui.dock_load(d, transmute([]byte)text)
	ui.end_frame()
	testing.expect(t, ok, "the file loads")

	dock_frames(&r, {"A"}, 3)

	sp := dock_space_of(&ctx)
	testing.expect_value(t, len(sp.root.tabs), 2)
	testing.expect_value(t, sp.root.active, 0)
	testing.expect_value(t, sp.root.tabs[0].title, "A")
}

@(test)
test_dock_layout_rides_the_settings_file :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	d := dock_frames(&r, {"A"}, 3)

	rig_open(&r)
	_, right := ui.dock_split(d, "", .Right, 0.4)
	ui.dock_panel(d, "B", right)
	ui.end_frame()
	dock_frames(&r, {"A", "B"}, 3)

	rig_open(&r)
	text := ui.settings_save_string(context.temp_allocator)
	ui.end_frame()
	testing.expect(
		t,
		strings.contains(text, "[dock.main]"),
		"the dockspace registers a settings handler",
	)

	other: ui.Context
	laid(&other)
	defer ui.destroy(&other)

	r2: Rig
	rig_open(&r2)
	loaded := ui.settings_load(transmute([]byte)text)
	ui.end_frame()
	testing.expect(t, loaded, "the settings file loads")

	dock_frames(&r2, {"A", "B"}, 3)

	sp := dock_space_of(&other)
	testing.expect(t, sp != nil, "the handler created the dockspace before it was declared")
	testing.expect_value(t, sp.root.kind, ui.Dock_Kind.Split)
	testing.expect(t, near(sp.root.ratio, 0.6), "the saved ratio is restored")
	testing.expect_value(t, len(sp.root.children[0].tabs), 1)
	testing.expect_value(t, len(sp.root.children[1].tabs), 1)
}

// ---- detach ----

@(test)
test_dock_cannot_detach_without_viewport_ops :: proc(t: ^testing.T) {
	ctx: ui.Context
	laid(&ctx)
	defer ui.destroy(&ctx)

	r: Rig
	dock_frames(&r, {"A", "B"}, 3, {mode = .Detachable})

	sp := dock_space_of(&ctx)
	testing.expect(t, !ui.dock_can_detach(), "a backend with no viewport ops cannot detach")
	testing.expect_value(t, sp.cfg.mode, ui.Dock_Mode.In_Window)

	tab := dock_tab_node(sp, sp.root, "B")
	dock_drag_to(&r, {"A", "B"}, dock_center(tab.rect), {700, 520}, {mode = .Detachable})

	testing.expect_value(t, len(sp.root.tabs), 2)
	testing.expect_value(t, ui.viewport_count(), 0)
}

@(test)
test_dock_detach_opens_a_viewport_draw_list :: proc(t: ^testing.T) {
	f: Fake_Vp
	ctx: ui.Context
	ui.init(&ctx, ui.Config{backend = fake_viewport_backend(&f)})
	defer ui.destroy(&ctx)

	cfg := ui.Dock_Config {
		mode = .Detachable,
	}
	r: Rig
	dock_frames(&r, {"A", "B"}, 3, cfg)

	testing.expect(t, ui.dock_can_detach(), "viewport ops enable detaching")

	sp := dock_space_of(&ctx)
	tab := dock_tab_node(sp, sp.root, "B")
	dock_drag_to(&r, {"A", "B"}, dock_center(tab.rect), {700, 520}, cfg)

	testing.expect_value(t, f.created, 1)
	testing.expect_value(t, ui.viewport_count(), 1)
	testing.expect_value(t, len(sp.detached), 1)
	testing.expect_value(t, len(sp.root.tabs), 1)
	testing.expect_value(t, sp.detached[0].tabs[0].title, "B")

	rig_open(&r)
	dock_frame({"A", "B"}, cfg)
	ui.end_frame()
	lists := ui.end_frame_viewports()

	testing.expect_value(t, len(lists), 1)
	testing.expect(t, len(lists[0].list.cmds) > 0, "a detached panel emits its own draw list")
}

@(test)
test_dock_detached_panel_lays_out_in_window_local_space :: proc(t: ^testing.T) {
	f: Fake_Vp
	ctx: ui.Context
	ui.init(&ctx, ui.Config{backend = fake_viewport_backend(&f)})
	defer ui.destroy(&ctx)

	cfg := ui.Dock_Config {
		mode = .Detachable,
	}
	r: Rig
	dock_frames(&r, {"A", "B"}, 3, cfg)

	sp := dock_space_of(&ctx)
	tab := dock_tab_node(sp, sp.root, "B")
	dock_drag_to(&r, {"A", "B"}, dock_center(tab.rect), {700, 520}, cfg)

	dock_frames(&r, {"A", "B"}, 2, cfg)

	v := ctx.viewports[0]
	testing.expect(t, v.node != nil, "the detached panel binds its node to the viewport")
	testing.expect(t, v.node.viewport == v, "the panel subtree belongs to the viewport space")
	testing.expect(
		t,
		near(v.node.rect.x, 0) && near(v.node.rect.y, ui.DOCK_TAB_H),
		"a detached panel sits under its own tab bar at the window origin",
	)
	testing.expect(t, near(v.node.rect.w, v.rect.w), "it fills the window width")
}

@(test)
test_dock_os_close_redocks_the_panel :: proc(t: ^testing.T) {
	f: Fake_Vp
	ctx: ui.Context
	ui.init(&ctx, ui.Config{backend = fake_viewport_backend(&f)})
	defer ui.destroy(&ctx)

	cfg := ui.Dock_Config {
		mode = .Detachable,
	}
	r: Rig
	dock_frames(&r, {"A", "B"}, 3, cfg)

	sp := dock_space_of(&ctx)
	tab := dock_tab_node(sp, sp.root, "B")
	dock_drag_to(&r, {"A", "B"}, dock_center(tab.rect), {700, 520}, cfg)
	testing.expect_value(t, ui.viewport_count(), 1)

	f.ev.closed = true
	dock_frames(&r, {"A", "B"}, 1, cfg)
	f.ev.closed = false

	testing.expect_value(t, ui.viewport_count(), 0)
	testing.expect_value(t, f.destroyed, 1)
	testing.expect_value(t, len(sp.detached), 0)
	testing.expect_value(t, len(sp.root.tabs), 2)
}

@(test)
test_dock_detached_panel_keeps_its_scroll :: proc(t: ^testing.T) {
	f: Fake_Vp
	ctx: ui.Context
	ui.init(&ctx, ui.Config{backend = fake_viewport_backend(&f)})
	defer ui.destroy(&ctx)

	cfg := ui.Dock_Config {
		mode = .Detachable,
	}

	build :: proc(cfg: ui.Dock_Config) -> ^ui.Node {
		out: ^ui.Node
		d := ui.dockspace(DOCK_ID, cfg, {props = {w = ui.Px(DOCK_W), h = ui.Px(DOCK_H)}})
		if ui.panel(d, "A") {
			ui.end_panel()
		}
		if ui.panel(d, "B") {
			out = ui.scroll({key = "sc"}).node
			for i in 0 ..< 20 {
				ui.push_id_int(i64(i))
				ui.leaf({key = "row", props = {w = ui.STRETCH, h = ui.Px(30)}})
				ui.pop_id()
			}
			ui.end()
			ui.end_panel()
		}
		return out
	}

	r: Rig
	for _ in 0 ..< 3 {
		rig_open(&r)
		build(cfg)
		ui.end_frame()
	}

	sp := dock_space_of(&ctx)
	sp.root.active = 1
	for _ in 0 ..< 2 {
		rig_open(&r)
		build(cfg)
		ui.end_frame()
	}

	sc: ^ui.Node
	rig_open(&r)
	sc = build(cfg)
	ui.end_frame()
	testing.expect(t, sc != nil, "the scroll container exists while B is active")
	sc.scroll.y = 40

	tab := dock_tab_node(sp, sp.root, "B")
	testing.expect(t, tab != nil, "B has a tab to drag")

	move(&r, tab.rect.x + tab.rect.w * 0.5, tab.rect.y + tab.rect.h * 0.5)
	press(&r)
	for i in 0 ..< 4 {
		if i == 1 {
			move(&r, 700, 520)
		}
		if i == 3 {
			release(&r)
		}
		rig_open(&r)
		build(cfg)
		ui.end_frame()
	}

	rig_open(&r)
	after := build(cfg)
	ui.end_frame()

	testing.expect_value(t, len(sp.detached), 1)
	testing.expect(t, after == sc, "the panel keeps its node identity across the detach")
	testing.expect(t, near(after.scroll.y, 40), "per-node scroll survives the detach")
}
