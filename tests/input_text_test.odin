package tests

import "core:mem"
import "core:testing"
import ui "../loom"

INPUT_W :: f32(200)
VIEW_X :: f32(9)

input_tree :: proc(buf: ^[dynamic]byte, ph: string = "") -> ui.Interaction {
	ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
	return ui.input(buf, {key = "in", props = {w = ui.Px(INPUT_W)}}, ph)
}

in_frame :: proc(r: ^Rig, buf: ^[dynamic]byte, ph: string = "") -> ui.Interaction {
	rig_open(r)
	it := input_tree(buf, ph)
	ui.end_frame()
	return it
}

settle :: proc(r: ^Rig, buf: ^[dynamic]byte) {
	rig_open(r, 2)
	input_tree(buf)
	ui.end_frame()
}

click_input :: proc(r: ^Rig, buf: ^[dynamic]byte, x: f32) -> ui.Interaction {
	settle(r, buf)
	move(r, x, 10)
	press(r)
	in_frame(r, buf)
	release(r)
	return in_frame(r, buf)
}

focus_input :: proc(r: ^Rig, buf: ^[dynamic]byte) -> ui.Interaction {
	move(r, VIEW_X + 150, 10)
	in_frame(r, buf)
	in_frame(r, buf)
	return click_input(r, buf, VIEW_X + 150)
}

st_of :: proc(it: ui.Interaction) -> ^ui.Input_State {
	return ui.state_of(it.node, ui.Input_State)
}

hold :: proc(r: ^Rig, buf: ^[dynamic]byte, k: ui.Key) -> ui.Interaction {
	tap(r, k)
	it := in_frame(r, buf)
	untap(r, k)
	return it
}

// ---- typing ----

@(test)
test_input_types_into_the_callers_buffer :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)

	r: Rig
	it := focus_input(&r, &buf)
	testing.expect(t, it.focused, "clicking the field focuses it")

	typed(&r, "abc")
	it = in_frame(&r, &buf)

	testing.expect_value(t, ui.buf_text(&buf), "abc")
	testing.expect(t, it.changed, "a buffer mutation reports changed")
	testing.expect_value(t, st_of(it).caret, 3)

	it = in_frame(&r, &buf)
	testing.expect(t, !it.changed, "changed is a one-frame edge")
}

@(test)
test_input_caret_lands_only_on_rune_boundaries :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)

	r: Rig
	it := focus_input(&r, &buf)

	typed(&r, "é☃")
	it = in_frame(&r, &buf)
	testing.expect_value(t, len(ui.buf_text(&buf)), 5)
	testing.expect_value(t, st_of(it).caret, 5)

	it = hold(&r, &buf, .Left)
	testing.expect_value(t, st_of(it).caret, 2)

	it = hold(&r, &buf, .Left)
	testing.expect_value(t, st_of(it).caret, 0)

	it = hold(&r, &buf, .Left)
	testing.expect_value(t, st_of(it).caret, 0)

	it = hold(&r, &buf, .Right)
	testing.expect_value(t, st_of(it).caret, 2)
}

@(test)
test_input_selection_is_replaced_by_typing :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)

	r: Rig
	focus_input(&r, &buf)
	typed(&r, "abcd")
	in_frame(&r, &buf)

	mods_set(&r, .Shift)
	hold(&r, &buf, .Left)
	it := hold(&r, &buf, .Left)
	mods_clear(&r)
	testing.expect_value(t, st_of(it).caret, 2)
	testing.expect_value(t, st_of(it).anchor, 4)

	typed(&r, "X")
	it = in_frame(&r, &buf)
	testing.expect_value(t, ui.buf_text(&buf), "abX")
	testing.expect_value(t, st_of(it).caret, 3)
}

@(test)
test_input_backspace_eats_a_selection_not_a_rune :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)

	r: Rig
	focus_input(&r, &buf)
	typed(&r, "hello")
	in_frame(&r, &buf)

	mods_set(&r, .Ctrl)
	hold(&r, &buf, .A)
	mods_clear(&r)

	it := hold(&r, &buf, .Backspace)
	testing.expect_value(t, ui.buf_text(&buf), "")
	testing.expect_value(t, st_of(it).caret, 0)
}

@(test)
test_input_home_and_end :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)

	r: Rig
	focus_input(&r, &buf)
	typed(&r, "hello")
	in_frame(&r, &buf)

	it := hold(&r, &buf, .Home)
	testing.expect_value(t, st_of(it).caret, 0)

	mods_set(&r, .Shift)
	it = hold(&r, &buf, .End)
	mods_clear(&r)
	testing.expect_value(t, st_of(it).caret, 5)
	testing.expect_value(t, st_of(it).anchor, 0)
}

@(test)
test_input_word_movement :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)

	r: Rig
	focus_input(&r, &buf)
	typed(&r, "one two")
	in_frame(&r, &buf)

	mods_set(&r, .Ctrl)
	it := hold(&r, &buf, .Left)
	testing.expect_value(t, st_of(it).caret, 4)
	it = hold(&r, &buf, .Left)
	testing.expect_value(t, st_of(it).caret, 0)
	it = hold(&r, &buf, .Right)
	mods_clear(&r)
	testing.expect_value(t, st_of(it).caret, 4)
}

// ---- clipboard ----

@(test)
test_input_copy_and_paste_round_trip :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)

	r: Rig
	focus_input(&r, &buf)
	typed(&r, "abc")
	in_frame(&r, &buf)

	mods_set(&r, .Ctrl)
	hold(&r, &buf, .A)
	hold(&r, &buf, .C)
	mods_clear(&r)
	testing.expect_value(t, string(p.buf[:]), "abc")

	hold(&r, &buf, .End)
	mods_set(&r, .Ctrl)
	it := hold(&r, &buf, .V)
	mods_clear(&r)

	testing.expect_value(t, ui.buf_text(&buf), "abcabc")
	testing.expect(t, it.changed, "a paste reports changed")
}

@(test)
test_input_cut_removes_the_selection :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)

	r: Rig
	focus_input(&r, &buf)
	typed(&r, "abcd")
	in_frame(&r, &buf)

	mods_set(&r, .Shift)
	hold(&r, &buf, .Left)
	hold(&r, &buf, .Left)
	mods_clear(&r)

	mods_set(&r, .Ctrl)
	hold(&r, &buf, .X)
	mods_clear(&r)

	testing.expect_value(t, ui.buf_text(&buf), "ab")
	testing.expect_value(t, string(p.buf[:]), "cd")
}

// ---- undo and redo ----

@(test)
test_input_typing_coalesces_into_one_undo :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)

	r: Rig
	focus_input(&r, &buf)
	for s in ([]string{"a", "b", "c"}) {
		typed(&r, s)
		in_frame(&r, &buf)
	}
	testing.expect_value(t, ui.buf_text(&buf), "abc")

	mods_set(&r, .Ctrl)
	it := hold(&r, &buf, .Z)
	mods_clear(&r)

	testing.expect_value(t, ui.buf_text(&buf), "")
	testing.expect(t, it.changed, "an undo reports changed")
	testing.expect_value(t, st_of(it).caret, 0)
}

@(test)
test_input_undo_past_the_start_is_a_no_op :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)

	r: Rig
	focus_input(&r, &buf)
	typed(&r, "ab")
	in_frame(&r, &buf)

	mods_set(&r, .Ctrl)
	hold(&r, &buf, .Z)
	it := hold(&r, &buf, .Z)
	mods_clear(&r)

	testing.expect_value(t, ui.buf_text(&buf), "")
	testing.expect_value(t, st_of(it).caret, 0)
}

@(test)
test_input_a_paste_starts_a_fresh_undo_entry :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)
	append(&p.buf, "ZZ")

	r: Rig
	focus_input(&r, &buf)
	typed(&r, "ab")
	in_frame(&r, &buf)

	mods_set(&r, .Ctrl)
	hold(&r, &buf, .V)
	mods_clear(&r)
	testing.expect_value(t, ui.buf_text(&buf), "abZZ")

	mods_set(&r, .Ctrl)
	hold(&r, &buf, .Z)
	mods_clear(&r)
	testing.expect_value(t, ui.buf_text(&buf), "ab")

	mods_set(&r, .Ctrl)
	hold(&r, &buf, .Z)
	mods_clear(&r)
	testing.expect_value(t, ui.buf_text(&buf), "")
}

@(test)
test_input_redo_and_a_new_edit_clears_it :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)

	r: Rig
	focus_input(&r, &buf)
	typed(&r, "ab")
	in_frame(&r, &buf)

	mods_set(&r, .Ctrl)
	hold(&r, &buf, .Z)
	testing.expect_value(t, ui.buf_text(&buf), "")
	hold(&r, &buf, .Y)
	mods_clear(&r)
	testing.expect_value(t, ui.buf_text(&buf), "ab")

	mods_set(&r, .Ctrl)
	hold(&r, &buf, .Z)
	mods_clear(&r)
	testing.expect_value(t, ui.buf_text(&buf), "")

	typed(&r, "z")
	in_frame(&r, &buf)
	testing.expect_value(t, ui.buf_text(&buf), "z")

	mods_set(&r, .Ctrl)
	hold(&r, &buf, .Y)
	mods_clear(&r)
	testing.expect_value(t, ui.buf_text(&buf), "z")
}

// ---- mouse ----

@(test)
test_input_click_places_the_caret_at_the_nearest_boundary :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)
	ui.buf_set(&buf, "hello")

	r: Rig
	move(&r, VIEW_X + 150, 10)
	in_frame(&r, &buf)
	in_frame(&r, &buf)

	it := click_input(&r, &buf, VIEW_X + 26)
	testing.expect_value(t, st_of(it).caret, 3)

	it = click_input(&r, &buf, VIEW_X + 24)
	testing.expect_value(t, st_of(it).caret, 2)
}

@(test)
test_input_double_click_selects_a_word :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)
	ui.buf_set(&buf, "one two")

	r: Rig
	move(&r, VIEW_X + 50, 10)
	in_frame(&r, &buf)
	in_frame(&r, &buf)

	press(&r)
	rig_open(&r, 0)
	input_tree(&buf)
	ui.end_frame()
	release(&r)
	rig_open(&r, 0)
	input_tree(&buf)
	ui.end_frame()

	press(&r)
	rig_open(&r, 0)
	input_tree(&buf)
	ui.end_frame()
	release(&r)
	rig_open(&r, 0)
	it := input_tree(&buf)
	ui.end_frame()

	testing.expect(t, it.double_clicked, "the second click is a double click")
	testing.expect_value(t, st_of(it).anchor, 4)
	testing.expect_value(t, st_of(it).caret, 7)
}

// ---- view, placeholder, caret ----

@(test)
test_input_scrolls_to_keep_the_caret_visible :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)

	r: Rig
	it := focus_input(&r, &buf)
	testing.expect_value(t, st_of(it).scroll_x, f32(0))

	typed(&r, "0123456789abcdefghijklmnop")
	it = in_frame(&r, &buf)
	it = in_frame(&r, &buf)

	st := st_of(it)
	testing.expect(t, st.scroll_x > 0, "the view scrolled to follow the caret")

	view := ui.find(ui.hash_string(it.id, "view"))
	testing.expect(t, view != nil, "the input has a clipped view node")
	caret := ui.find(ui.hash_string(ui.hash_string(it.id, "view"), "car"))
	testing.expect(t, caret != nil, "the input has a caret node")
	testing.expect(
		t,
		caret.rect.x >= view.rect.x - 1 && caret.rect.x <= view.rect.x + view.rect.w,
		"the caret stays inside the view",
	)
}

@(test)
test_input_shows_a_placeholder_while_empty :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)

	r: Rig
	move(&r, 700, 500)
	rig_open(&r)
	input_tree(&buf, "Search")
	list := ui.end_frame()

	found := false
	for cmd in list.cmds {
		if v, ok := cmd.(ui.Cmd_Text); ok && v.text == "Search" {
			found = true
			testing.expect_value(t, v.color, ui.theme().text_faint)
		}
	}
	testing.expect(t, found, "the placeholder paints while the buffer is empty")

	ui.buf_set(&buf, "x")
	rig_open(&r)
	input_tree(&buf, "Search")
	list = ui.end_frame()
	for cmd in list.cmds {
		if v, ok := cmd.(ui.Cmd_Text); ok {
			testing.expect(t, v.text != "Search", "the placeholder is gone once there is text")
		}
	}
}

@(test)
test_input_selection_highlight_sits_under_the_text :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)

	r: Rig
	focus_input(&r, &buf)
	typed(&r, "hello")
	in_frame(&r, &buf)

	mods_set(&r, .Ctrl)
	hold(&r, &buf, .A)
	mods_clear(&r)
	it := in_frame(&r, &buf)

	sel := ui.find(ui.hash_string(ui.hash_string(it.id, "view"), "sel"))
	testing.expect(t, sel != nil, "the selection node exists")
	testing.expect(t, near(sel.rect.w, 5 * CHAR_W), "it spans the whole selection")
	testing.expect_value(t, sel.computed.bg.(ui.Color), ui.theme().selection)
}

@(test)
test_disabled_input_ignores_typing :: proc(t: ^testing.T) {
	p: Clip_Probe
	ctx: ui.Context
	clipped(&ctx, &p)
	defer clip_free(&p)
	defer ui.destroy(&ctx)

	buf := make([dynamic]byte)
	defer delete(buf)

	build :: proc(buf: ^[dynamic]byte) -> ui.Interaction {
		ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600), dir = .Column}})
		return ui.input(buf, {key = "in", flags = {.Disabled}, props = {w = ui.Px(INPUT_W)}})
	}

	r: Rig
	move(&r, 20, 10)
	rig_open(&r)
	it := build(&buf)
	ui.end_frame()

	ui.set_focus(it.id)
	typed(&r, "abc")
	rig_open(&r)
	build(&buf)
	ui.end_frame()

	testing.expect_value(t, ui.buf_text(&buf), "")
}

// ---- lifetime ----

@(test)
test_input_state_leaks_nothing :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	{
		alloc := mem.tracking_allocator(&track)
		p: Clip_Probe
		ctx: ui.Context
		clipped(&ctx, &p, alloc)

		buf := make([dynamic]byte, alloc)

		r: Rig
		focus_input(&r, &buf)
		for s in ([]string{"alpha ", "beta ", "gamma"}) {
			typed(&r, s)
			in_frame(&r, &buf)
			in_frame(&r, &buf)
		}

		mods_set(&r, .Ctrl)
		hold(&r, &buf, .Z)
		hold(&r, &buf, .Z)
		mods_clear(&r)

		for _ in 0 ..< 8 {
			rig_open(&r)
			ui.leaf({key = "root", props = {w = ui.Px(800), h = ui.Px(600)}})
			ui.end_frame()
		}

		delete(buf)
		ui.destroy(&ctx)
		clip_free(&p)
	}

	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}
