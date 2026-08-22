package tests

import "core:mem"
import "core:strings"
import "core:testing"
import ui "../loom"

VIEWPORT :: ui.Vec2{800, 600}

Fold :: struct {
	open:  bool,
	count: int,
}

Caret :: struct {
	pos: int,
}

setup :: proc(ctx: ^ui.Context, prune_after: u32 = 0, allocator := context.allocator) {
	ui.init(ctx, ui.Config{backend = ui.noop_backend(), prune_after = prune_after}, allocator)
}

open_frame :: proc() {
	ui.begin_frame(ui.Input{dt = 1.0 / 60.0, viewport = VIEWPORT, dpi = 1})
}

@(test)
test_tree_shape :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "sidebar", props = {dir = .Column, bg = ui.hex(0x1C1C21), pad = ui.all(12)}})
	ui.leaf({key = "title", text = "Library"})
	ui.leaf({key = "songs", flags = {.Clickable}, props = {bg = ui.hex(0x6366F1)}})
	ui.end()
	ui.leaf({key = "content", props = {dir = .Row}})
	ui.end_frame()

	dump := ui.dump_tree_string(context.temp_allocator)
	expected := `#loom.root [Row] rect(0,0,800,600)
  #sidebar [Column] rect(0,0,24,600) bg=#1C1C21FF pad=(12,12,12,12)
    #title [Row] rect(12,12,0,0) text="Library"
    #songs [Row] rect(12,12,0,0) bg=#6366F1FF flags=[Clickable]
  #content [Row] rect(24,0,0,600)
`
	testing.expect_value(t, dump, expected)
}

@(test)
test_ids_are_structural :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "a"})
	inner_a := ui.leaf({key = "row"}).id
	ui.end()
	ui.begin({key = "b"})
	inner_b := ui.leaf({key = "row"}).id
	ui.end()
	ui.end_frame()

	testing.expect(t, inner_a != inner_b, "the same key under two parents must give two ids")

	open_frame()
	ui.begin({key = "a"})
	again := ui.leaf({key = "row"}).id
	ui.end()
	ui.begin({key = "b"})
	ui.leaf({key = "row"})
	ui.end()
	ui.end_frame()

	testing.expect_value(t, again, inner_a)
}

@(test)
test_push_id_scopes :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.push_id("left")
	a := ui.leaf({key = "item"}).id
	ui.pop_id()
	ui.push_id_int(7)
	b := ui.leaf({key = "item"}).id
	ui.pop_id()
	c := ui.leaf({key = "item"}).id
	ui.end_frame()

	testing.expect(t, a != b && b != c && a != c, "push_id must discriminate identical keys")
}

@(test)
test_state_survives_a_missing_frame :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx, 2)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "details"})
	f := ui.state(Fold)
	f.open = true
	f.count = 42
	ui.end()
	ui.end_frame()

	open_frame()
	ui.end_frame()

	open_frame()
	ui.begin({key = "details"})
	back := ui.state(Fold)
	ui.end()
	ui.end_frame()

	testing.expect_value(t, back.open, true)
	testing.expect_value(t, back.count, 42)
}

@(test)
test_state_is_gone_after_prune :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx, 2)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "details"})
	f := ui.state(Fold)
	f.count = 99
	ui.end()
	ui.end_frame()

	for _ in 0 ..< 4 {
		open_frame()
		ui.end_frame()
	}

	open_frame()
	ui.begin({key = "details"})
	back := ui.state(Fold)
	ui.end()
	ui.end_frame()

	testing.expect_value(t, back.count, 0)
	testing.expect_value(t, back.open, false)
}

@(test)
test_two_state_types_on_one_node :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "field"})
	f1 := ui.state(Fold)
	c1 := ui.state(Caret)
	f2 := ui.state(Fold)
	f1.count = 3
	c1.pos = 11
	ui.end()
	ui.end_frame()

	testing.expect(t, rawptr(f1) == rawptr(f2), "the same type must return the same block")
	testing.expect(t, rawptr(f1) != rawptr(c1), "different types must return different blocks")
	testing.expect_value(t, f2.count, 3)
	testing.expect_value(t, c1.pos, 11)
}

TRACKS_A :: []string{"alpha", "beta", "gamma"}
TRACKS_B :: []string{"gamma", "alpha", "beta"}

build_rows :: proc(tracks: []string, stamp: bool) {
	for name in tracks {
		ui.begin({key = name})
		s := ui.state(Fold)
		if stamp {
			s.count = len(name)
		}
		ui.end()
	}
}

@(test)
test_keyed_reorder_keeps_state_with_the_key :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	build_rows(TRACKS_A, true)
	ui.end_frame()

	open_frame()
	build_rows(TRACKS_B, false)
	ui.end_frame()

	dump := ui.dump_tree_string(context.temp_allocator)
	expected := `#loom.root [Row] rect(0,0,800,600)
  #gamma [Row] rect(0,0,0,600)
  #alpha [Row] rect(0,0,0,600)
  #beta [Row] rect(0,0,0,600)
`
	testing.expect_value(t, dump, expected)

	open_frame()
	for name in TRACKS_B {
		ui.begin({key = name})
		s := ui.state(Fold)
		testing.expect_value(t, s.count, len(name))
		ui.end()
	}
	ui.end_frame()
}

@(test)
test_node_count_is_stable_over_many_frames :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)

	settled: ui.Stats
	for i in 0 ..< 100 {
		open_frame()
		build_twenty()
		ui.end_frame()

		if i == 3 {
			settled = ui.stats()
		}
	}

	final := ui.stats()
	testing.expect_value(t, final.live_nodes, settled.live_nodes)
	testing.expect_value(t, final.state_blocks, settled.state_blocks)
	testing.expect_value(t, final.live_nodes, 21)
	testing.expect_value(t, final.frame_index, u64(100))
}

build_twenty :: proc() {
	for i in 0 ..< 4 {
		ui.push_id_int(i64(i))
		ui.begin({key = "group", props = {dir = .Column}})
		for j in 0 ..< 4 {
			ui.push_id_int(i64(j))
			ui.leaf({key = "cell"})
			ui.pop_id()
		}
		ui.end()
		ui.pop_id()
	}
}

@(test)
test_dropped_branch_is_evicted_and_recycled :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx, 2)
	defer ui.destroy(&ctx)

	for _ in 0 ..< 3 {
		open_frame()
		ui.begin({key = "branch"})
		ui.leaf({key = "one"})
		ui.leaf({key = "two"})
		ui.end()
		ui.end_frame()
	}
	with_branch := ui.stats()
	testing.expect_value(t, with_branch.live_nodes, 4)

	for _ in 0 ..< 5 {
		open_frame()
		ui.end_frame()
	}

	after := ui.stats()
	testing.expect_value(t, after.live_nodes, 1)
	testing.expect_value(t, after.free_nodes, 3)
	testing.expect_value(t, after.state_blocks, 0)

	open_frame()
	ui.begin({key = "branch"})
	ui.leaf({key = "one"})
	ui.leaf({key = "two"})
	ui.end()
	ui.end_frame()

	reused := ui.stats()
	testing.expect_value(t, reused.live_nodes, 4)
	testing.expect_value(t, reused.free_nodes, 0)
}

@(test)
test_find_and_current :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	it := ui.begin({key = "panel"})
	testing.expect(t, ui.current() == it.node, "current must be the open node")
	testing.expect_value(t, ui.current_id(), it.id)
	ui.end()
	testing.expect(t, ui.current() == ui.root(), "current must fall back to the root")
	ui.end_frame()

	testing.expect(t, ui.find(it.id) == it.node, "find must return the retained node")
	testing.expect(t, ui.find(ui.Id(1234567)) == nil, "find must return nil for an unknown id")
}

@(test)
test_destroy_leaks_nothing :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	{
		ctx: ui.Context
		setup(&ctx, 2, mem.tracking_allocator(&track))

		for _ in 0 ..< 20 {
			open_frame()
			build_twenty()
			ui.begin({key = "transient"})
			s := ui.state(Caret)
			s.pos += 1
			ui.end()
			ui.end_frame()
		}
		ui.destroy(&ctx)
	}

	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
test_colors_and_edges :: proc(t: ^testing.T) {
	testing.expect_value(t, ui.hex(0x18181B), ui.Color{0x18, 0x18, 0x1B, 255})
	testing.expect_value(t, ui.rgb(1, 2, 3), ui.Color{1, 2, 3, 255})
	testing.expect_value(t, ui.rgba(1, 2, 3, 4), ui.Color{1, 2, 3, 4})

	half := ui.fade(ui.rgb(10, 20, 30), 0.5)
	testing.expect_value(t, half, ui.Color{10, 20, 30, 128})
	testing.expect_value(t, ui.fade(half, 0.5), ui.Color{10, 20, 30, 64})

	testing.expect_value(t, ui.all(12), ui.Edges{12, 12, 12, 12})
	testing.expect_value(t, ui.xy(16, 8), ui.Edges{16, 8, 16, 8})
	testing.expect_value(t, ui.ltrb(1, 2, 3, 4), ui.Edges{1, 2, 3, 4})
	testing.expect_value(t, ui.rad(6), ui.Radius{6, 6, 6, 6})
	testing.expect_value(t, ui.rad4(1, 2, 3, 4), ui.Radius{1, 2, 3, 4})
}

@(test)
test_scope_closes_at_end_of_scope :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	scoped_body()
	ui.leaf({key = "sibling"})
	ui.end_frame()

	dump := ui.dump_tree_string(context.temp_allocator)
	expected := `#loom.root [Row] rect(0,0,800,600)
  #outer [Column] rect(0,0,0,600)
    #inner [Row] rect(0,0,0,0)
  #sibling [Row] rect(0,0,0,600)
`
	testing.expect_value(t, dump, expected)
}

scoped_body :: proc() {
	ui.scope({key = "outer", props = {dir = .Column}})
	ui.leaf({key = "inner"})
}

@(test)
test_custom_stores_its_callback :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)

	marker := 0
	open_frame()
	it := ui.custom({key = "canvas"}, proc(node: ^ui.Node, user: rawptr) {
			(^int)(user)^ = 7
		}, &marker)
	ui.end_frame()

	testing.expect(t, it.node.draw != nil, "custom must store the callback on the node")
	it.node.draw(it.node, it.node.draw_user)
	testing.expect_value(t, marker, 7)
}

@(test)
test_writer_accepts_a_builder :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.leaf({key = "only"})
	ui.end_frame()

	b := strings.builder_make(context.temp_allocator)
	ui.dump_tree(strings.to_writer(&b))
	testing.expect(t, strings.contains(strings.to_string(b), "#only"), "dump_tree must write through a Writer")
}
