package tests

import "core:strings"
import "core:testing"
import "core:unicode/utf8"
import ui "../loom"

texted :: proc(ctx: ^ui.Context, p: ui.Props, allocator := context.allocator) {
	root := p
	if root.font_size == 0 {
		root.font_size = 16
	}
	ui.init(ctx, ui.Config{backend = fake_backend(), root = root}, allocator)
}

run_texts :: proc(n: ^ui.Node, allocator := context.allocator) -> []string {
	runs := ui.text_runs(n)
	out := make([]string, len(runs), allocator)
	for r, i in runs {
		out[i] = r.text
	}
	return out
}

expect_runs :: proc(t: ^testing.T, n: ^ui.Node, want: []string, loc := #caller_location) {
	got := run_texts(n, context.temp_allocator)
	if !testing.expectf(t, len(got) == len(want), "got runs %q, want %q", got, want, loc = loc) {
		return
	}
	for s, i in got {
		testing.expectf(t, s == want[i], "run %d is %q, want %q", i, s, want[i], loc = loc)
	}
}

label_in :: proc(box: ui.Props, text: string, p: ui.Props) -> ^ui.Node {
	ui.begin({key = "box", props = box})
	n := ui.leaf({key = "label", text = text, props = p}).node
	ui.end()
	return n
}

@(test)
test_words_break_where_hand_calculation_says :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	n := label_in({w = ui.Px(100), h = ui.FIT}, "aaa bbb ccc ddd", {})
	ui.end_frame()

	expect_runs(t, n, {"aaa bbb", "ccc ddd"})
	testing.expect_value(t, n.rect.h, f32(32))
}

@(test)
test_words_collapse_runs_of_spaces :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	n := label_in({w = ui.Px(100), h = ui.FIT}, "aa   bb", {})
	ui.end_frame()

	expect_runs(t, n, {"aa   bb"})
	testing.expect_value(t, len(ui.text_runs(n)), 1)
}

@(test)
test_long_word_overflows_and_is_reported :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	n := label_in({w = ui.Px(100), h = ui.FIT}, "hi supercalifragilistic", {})
	ui.end_frame()

	expect_runs(t, n, {"hi", "supercalifragilistic"})

	got := ui.measure("hi supercalifragilistic", {}, 100)
	testing.expect_value(t, got.x, f32(200))
	testing.expect_value(t, got.y, f32(32))
	_ = n
}

@(test)
test_wrap_none_keeps_newlines_on_one_line :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	n := label_in({w = ui.Px(50), h = ui.FIT}, "aaa\nbbb", {text_wrap = .None})
	ui.end_frame()

	expect_runs(t, n, {"aaa\nbbb"})
	testing.expect_value(t, n.rect.h, f32(16))
}

@(test)
test_newline_breaks_in_words_and_chars :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "box", props = {w = ui.Px(200), h = ui.FIT, dir = .Column}})
	words := ui.leaf({key = "w", text = "aaa\nbbb", props = {text_wrap = .Words}}).node
	chars := ui.leaf({key = "c", text = "aaa\nbbb", props = {text_wrap = .Chars}}).node
	ui.end()
	ui.end_frame()

	expect_runs(t, words, {"aaa", "bbb"})
	expect_runs(t, chars, {"aaa", "bbb"})
}

@(test)
test_chars_break_on_rune_boundaries :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	n := label_in({w = ui.Px(30), h = ui.FIT}, "привет", {text_wrap = .Chars})
	ui.end_frame()

	expect_runs(t, n, {"при", "вет"})
	for r in ui.text_runs(n) {
		testing.expect(t, utf8.valid_string(r.text), "a .Chars break split a rune")
	}
}

@(test)
test_ellipsis_is_absent_when_the_text_fits :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	n := label_in({w = ui.Px(100), h = ui.FIT}, "Songs", {text_wrap = .Ellipsis})
	ui.end_frame()

	expect_runs(t, n, {"Songs"})
}

@(test)
test_ellipsis_truncates_at_the_boundary :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	n := label_in({w = ui.Px(50), h = ui.FIT}, "abcdefgh", {text_wrap = .Ellipsis})
	ui.end_frame()

	expect_runs(t, n, {"abcd", "…"})
	testing.expect_value(t, n.rect.h, f32(16))
}

@(test)
test_ellipsis_never_splits_a_rune :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	n := label_in({w = ui.Px(50), h = ui.FIT}, "привет мир", {text_wrap = .Ellipsis})
	ui.end_frame()

	runs := ui.text_runs(n)
	testing.expect_value(t, len(runs), 2)
	testing.expect_value(t, runs[1].text, ui.ELLIPSIS)
	testing.expect(t, utf8.valid_string(runs[0].text), "ellipsis cut split a rune")
	testing.expect_value(t, utf8.rune_count_in_string(runs[0].text), 4)
}

@(test)
test_ellipsis_ignores_newlines :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	n := label_in({w = ui.Px(200), h = ui.FIT}, "aaa\nbbb", {text_wrap = .Ellipsis})
	ui.end_frame()

	expect_runs(t, n, {"aaa\nbbb"})
}

@(test)
test_text_align_positions_runs :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "box", props = {w = ui.Px(100), h = ui.FIT, dir = .Column}})
	start := ui.leaf({key = "s", text = "ab", props = {text_align = .Start}}).node
	center := ui.leaf({key = "c", text = "ab", props = {text_align = .Center}}).node
	tail := ui.leaf({key = "e", text = "ab", props = {text_align = .End}}).node
	ui.end()
	ui.end_frame()

	testing.expect_value(t, ui.text_runs(start)[0].pos.x, f32(0))
	testing.expect_value(t, ui.text_runs(center)[0].pos.x, f32(40))
	testing.expect_value(t, ui.text_runs(tail)[0].pos.x, f32(80))
}

@(test)
test_justify_spreads_words_and_exempts_last_line :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	n := label_in({w = ui.Px(100), h = ui.FIT}, "aaa bbb ccc ddd", {text_align = .Justify})
	ui.end_frame()

	runs := ui.text_runs(n)
	testing.expect_value(t, len(runs), 3)
	testing.expect_value(t, runs[0].text, "aaa")
	testing.expect_value(t, runs[0].pos.x, f32(0))
	testing.expect_value(t, runs[1].text, "bbb")
	testing.expect_value(t, runs[1].pos.x, f32(70))
	testing.expect_value(t, runs[2].text, "ccc ddd")
	testing.expect_value(t, runs[2].pos.x, f32(0))
}

@(test)
test_justify_exempts_newline_terminated_lines :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	n := label_in({w = ui.Px(100), h = ui.FIT}, "aa bb\ncc dd", {text_align = .Justify})
	ui.end_frame()

	expect_runs(t, n, {"aa bb", "cc dd"})
}

@(test)
test_baselines_line_up_across_font_sizes :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "row", props = {w = ui.Px(200), h = ui.FIT, align = .Baseline}})
	big := ui.leaf({key = "big", text = "A", props = {font_size = 20}}).node
	small := ui.leaf({key = "small", text = "b", props = {font_size = 10}}).node
	ui.end()
	ui.end_frame()

	testing.expect_value(t, ui.text_runs(big)[0].pos.y, f32(15))
	testing.expect_value(t, ui.text_runs(small)[0].pos.y, f32(15))
}

@(test)
test_line_height_scales_the_block :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	n := label_in({w = ui.Px(100), h = ui.FIT}, "aaa bbb ccc ddd", {line_height = 1.5})
	ui.end_frame()

	testing.expect_value(t, n.rect.h, f32(48))
	testing.expect_value(t, ui.text_runs(n)[1].pos.y, f32(36))
}

@(test)
test_letter_spacing_widens_text :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "col", props = {w = ui.FIT, h = ui.FIT, dir = .Column}})
	plain := ui.leaf({key = "p", text = "abcde", props = {w = ui.FIT}}).node
	spaced := ui.leaf({key = "s", text = "abcde", props = {w = ui.FIT, letter_spacing = 2}}).node
	ui.end()
	ui.end_frame()

	testing.expect_value(t, plain.rect.w, f32(50))
	testing.expect_value(t, spaced.rect.w, f32(60))
	testing.expect_value(t, ui.text_runs(spaced)[0].width, f32(60))
}

@(test)
test_measure_matches_the_laid_text_size :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {})
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "box", props = {w = ui.Px(100), h = ui.FIT}})
	got := ui.measure("aaa bbb ccc ddd", {}, 100)
	ui.leaf({key = "label", text = "aaa bbb ccc ddd"})
	ui.end()
	ui.end_frame()

	testing.expect_value(t, got.x, f32(70))
	testing.expect_value(t, got.y, f32(32))
}

@(test)
test_measure_inherits_from_the_open_node :: proc(t: ^testing.T) {
	ctx: ui.Context
	texted(&ctx, {font_size = 16})
	defer ui.destroy(&ctx)

	open_frame()
	ui.begin({key = "big", props = {font_size = 20}})
	root_side := ui.measure("abcde", {})
	ui.end()
	ui.end_frame()

	open_frame()
	ui.begin({key = "big", props = {font_size = 20}})
	got := ui.measure("abcde", {})
	ui.end()
	ui.end_frame()

	testing.expect_value(t, root_side.y, f32(16))
	testing.expect_value(t, got.x, f32(50))
	testing.expect_value(t, got.y, f32(20))
}

@(test)
test_static_tree_measures_only_once :: proc(t: ^testing.T) {
	calls := 0
	ctx: ui.Context
	ui.init(
		&ctx,
		ui.Config{backend = counting_backend(&calls), root = ui.Props{font_size = 16}},
	)
	defer ui.destroy(&ctx)

	names := make([]string, 200)
	defer delete(names)
	for i in 0 ..< len(names) {
		names[i] = strings.clone(fmt_index("row", i))
	}
	defer for s in names {
		delete(s)
	}

	build :: proc(names: []string) {
		ui.begin({key = "col", props = {w = ui.Px(400), h = ui.FIT, dir = .Column}})
		for s, i in names {
			ui.push_id_int(i64(i))
			ui.leaf({key = s, text = s})
			ui.pop_id()
		}
		ui.end()
	}

	open_frame()
	build(names)
	ui.end_frame()
	first := calls
	testing.expect(t, first > 0, "the first frame measured nothing")

	calls = 0
	open_frame()
	build(names)
	ui.end_frame()
	testing.expect_value(t, calls, 0)
	testing.expect_value(t, ui.stats().text_misses, 0)
}

@(test)
test_changing_one_label_remeasures_only_it :: proc(t: ^testing.T) {
	calls := 0
	ctx: ui.Context
	ui.init(
		&ctx,
		ui.Config{backend = counting_backend(&calls), root = ui.Props{font_size = 16}},
	)
	defer ui.destroy(&ctx)

	build :: proc(third: string) {
		ui.begin({key = "col", props = {w = ui.Px(400), h = ui.FIT, dir = .Column}})
		ui.leaf({key = "a", text = "alpha"})
		ui.leaf({key = "b", text = "beta"})
		ui.leaf({key = "c", text = third})
		ui.end()
	}

	open_frame()
	build("gamma")
	ui.end_frame()

	open_frame()
	build("gamma")
	ui.end_frame()

	calls = 0
	open_frame()
	build("delta")
	ui.end_frame()

	testing.expect_value(t, ui.stats().text_misses, 2)
	testing.expect(t, calls > 0 && calls <= 6, "one changed label should cost a handful of runs")
}

@(test)
test_stale_cache_entries_are_evicted :: proc(t: ^testing.T) {
	ctx: ui.Context
	ui.init(
		&ctx,
		ui.Config {
			backend = fake_backend(),
			root = ui.Props{font_size = 16},
			text_cache_frames = 2,
		},
	)
	defer ui.destroy(&ctx)

	open_frame()
	ui.leaf({key = "a", text = "alpha"})
	ui.end_frame()
	testing.expect(t, ui.stats().text_entries > 0, "nothing was cached")

	for _ in 0 ..< 5 {
		open_frame()
		ui.end_frame()
	}
	testing.expect_value(t, ui.stats().text_entries, 0)
}

fmt_index :: proc(prefix: string, i: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, prefix)
	strings.write_int(&b, i)
	return strings.to_string(b)
}
