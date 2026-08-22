package tests

import "core:os"
import "core:strings"
import "core:testing"
import ui "../loom"

saved :: proc(ctx: ^ui.Context) {
	ui.init(ctx, ui.Config{backend = ui.noop_backend()})
}

persisted_list :: proc(scroll: f32) -> ui.Interaction {
	ui.scope({key = "root", props = {w = ui.Px(800), h = ui.Px(600)}})
	list := ui.begin(
		{
			key = "library",
			flags = {.Scroll_Y, .Persist},
			props = {w = ui.Px(200), h = ui.Px(100), dir = .Column},
		},
	)
	if scroll >= 0 {
		list.node.scroll.y = scroll
	}
	for i in 0 ..< 10 {
		ui.push_id_int(i64(i))
		ui.leaf({props = {w = ui.STRETCH, h = ui.Px(30)}})
		ui.pop_id()
	}
	ui.end()
	return list
}

section_of :: proc(text, name: string) -> string {
	head := strings.index(text, name)
	if head < 0 {
		return ""
	}
	rest := text[head + len(name):]
	next := strings.index(rest, "\n[")
	if next < 0 {
		return rest
	}
	return rest[:next]
}

@(test)
test_an_empty_file_loads_nothing :: proc(t: ^testing.T) {
	ctx: ui.Context
	saved(&ctx)
	defer ui.destroy(&ctx)

	testing.expect(t, !ui.settings_load({}), "an empty file reports nothing loaded")
	testing.expect_value(t, ui.theme().name, "loom_dark")
}

@(test)
test_save_carries_the_version_and_active_theme :: proc(t: ^testing.T) {
	ctx: ui.Context
	saved(&ctx)
	defer ui.destroy(&ctx)

	ui.set_theme(ui.LOOM_LIGHT)
	text := ui.settings_save_string(context.temp_allocator)

	testing.expect(t, strings.contains(text, "[loom]"), "the file opens with [loom]")
	testing.expect(t, strings.contains(text, "version = 0.1"), "the version is written")
	testing.expect(t, strings.contains(text, "theme = loom_light"), "the active theme is written")
}

@(test)
test_saving_clears_the_dirty_flag :: proc(t: ^testing.T) {
	ctx: ui.Context
	saved(&ctx)
	defer ui.destroy(&ctx)

	ui.set_setting("window.size", ui.Vec2{1280, 720})
	testing.expect(t, ui.settings_is_dirty(), "a new setting marks the settings dirty")
	_ = ui.settings_save_string(context.temp_allocator)
	testing.expect(t, !ui.settings_is_dirty(), "saving clears the dirty flag")
}

@(test)
test_app_settings_round_trip :: proc(t: ^testing.T) {
	a: ui.Context
	saved(&a)

	ui.set_setting("window.size", ui.Vec2{1280, 720})
	ui.set_setting("sidebar.open", true)
	ui.set_setting("volume", f32(0.75))
	ui.set_setting("last_file", "D:/work/session.loom")
	text := ui.settings_save_string(context.temp_allocator)
	ui.destroy(&a)

	b: ui.Context
	saved(&b)
	defer ui.destroy(&b)

	testing.expect(t, ui.settings_load(transmute([]byte)text), "the file loaded")
	testing.expect_value(t, ui.setting_vec2("window.size"), ui.Vec2{1280, 720})
	testing.expect_value(t, ui.setting_bool("sidebar.open"), true)
	testing.expect_value(t, ui.setting_f32("volume"), f32(0.75))
	testing.expect_value(t, ui.setting_string("last_file"), "D:/work/session.loom")
	testing.expect_value(t, ui.setting_string("missing", "fallback"), "fallback")
	testing.expect(t, !ui.settings_is_dirty(), "loading does not dirty the settings")
}

@(test)
test_custom_theme_round_trips :: proc(t: ^testing.T) {
	a: ui.Context
	saved(&a)

	mine := ui.LOOM_LIGHT
	mine.name = "midnight"
	mine.accent = RED
	mine.bg = BLUE
	ui.set_theme(mine)
	text := ui.settings_save_string(context.temp_allocator)
	ui.destroy(&a)

	b: ui.Context
	saved(&b)
	defer ui.destroy(&b)

	testing.expect(t, ui.settings_load(transmute([]byte)text), "the file loaded")
	testing.expect_value(t, ui.theme().name, "midnight")
	testing.expect_value(t, ui.theme().accent, RED)
	testing.expect_value(t, ui.theme().bg, BLUE)
	testing.expect_value(t, ui.theme().text, ui.LOOM_LIGHT.text)
	testing.expect_value(t, ui.theme().dark, false)
}

@(test)
test_a_theme_section_starts_from_its_base :: proc(t: ^testing.T) {
	ctx: ui.Context
	saved(&ctx)
	defer ui.destroy(&ctx)

	file := `
[loom]
theme = paper

[theme.paper]
base = loom_light
accent = #FF0000
`
	testing.expect(t, ui.settings_load(transmute([]byte)file), "the file loaded")

	got, ok := ui.theme_by_name("paper")
	testing.expect(t, ok, "the theme was registered")
	testing.expect_value(t, got.accent, ui.Color{255, 0, 0, 255})
	testing.expect_value(t, got.bg, ui.LOOM_LIGHT.bg)
	testing.expect_value(t, got.text, ui.LOOM_LIGHT.text)
	testing.expect_value(t, ui.theme().name, "paper")
}

@(test)
test_alpha_colours_survive_the_round_trip :: proc(t: ^testing.T) {
	ctx: ui.Context
	saved(&ctx)
	defer ui.destroy(&ctx)

	file := `
[theme.glassy]
base = loom_dark
shadow = #01020304
`
	testing.expect(t, ui.settings_load(transmute([]byte)file), "the file loaded")

	got, _ := ui.theme_by_name("glassy")
	testing.expect_value(t, got.shadow, ui.Color{1, 2, 3, 4})
}

@(test)
test_node_scroll_round_trips :: proc(t: ^testing.T) {
	a: ui.Context
	saved(&a)

	open_frame()
	persisted_list(60)
	ui.end_frame()

	text := ui.settings_save_string(context.temp_allocator)
	ui.destroy(&a)

	testing.expect(t, strings.contains(text, "[node]"), "the node section is written")
	testing.expect(t, strings.contains(text, "library.scroll"), "the keyed path is written")

	b: ui.Context
	saved(&b)
	defer ui.destroy(&b)

	testing.expect(t, ui.settings_load(transmute([]byte)text), "the file loaded")

	open_frame()
	restored := persisted_list(-1)
	ui.end_frame()

	testing.expect_value(t, restored.node.scroll.y, f32(60))
}

@(test)
test_node_scroll_survives_a_prune :: proc(t: ^testing.T) {
	ctx: ui.Context
	ui.init(&ctx, ui.Config{backend = ui.noop_backend(), prune_after = 1})
	defer ui.destroy(&ctx)

	open_frame()
	persisted_list(60)
	ui.end_frame()

	for _ in 0 ..< 4 {
		open_frame()
		ui.end_frame()
	}

	open_frame()
	restored := persisted_list(-1)
	ui.end_frame()

	testing.expect_value(t, restored.node.scroll.y, f32(60))
}

@(test)
test_an_empty_node_entry_is_not_written :: proc(t: ^testing.T) {
	ctx: ui.Context
	saved(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	persisted_list(0)
	ui.end_frame()

	text := ui.settings_save_string(context.temp_allocator)
	testing.expect(t, !strings.contains(text, "[node]"), "a zero entry keeps the file quiet")
}

@(test)
test_saving_is_deterministic :: proc(t: ^testing.T) {
	ctx: ui.Context
	saved(&ctx)
	defer ui.destroy(&ctx)

	mine := ui.LOOM_DARK
	mine.name = "zebra"
	ui.register_theme(mine)
	other := ui.LOOM_LIGHT
	other.name = "alpaca"
	ui.register_theme(other)

	ui.set_setting("zulu", "last")
	ui.set_setting("alpha", "first")
	ui.set_setting("mike", "middle")

	open_frame()
	persisted_list(60)
	ui.end_frame()

	first := ui.settings_save_string(context.temp_allocator)
	second := ui.settings_save_string(context.temp_allocator)
	testing.expect_value(t, first, second)

	testing.expect(
		t,
		strings.index(first, "[theme.alpaca]") < strings.index(first, "[theme.zebra]"),
		"themes are written in name order",
	)

	app := section_of(first, "[app]")
	testing.expect(
		t,
		strings.index(app, "alpha") < strings.index(app, "mike") &&
		strings.index(app, "mike") < strings.index(app, "zulu"),
		"app settings are written in key order",
	)

	testing.expect(t, ui.settings_load(transmute([]byte)first), "the file loaded")
	third := ui.settings_save_string(context.temp_allocator)
	testing.expect_value(t, third, first)
}

@(test)
test_junk_is_skipped_without_losing_the_rest :: proc(t: ^testing.T) {
	ctx: ui.Context
	saved(&ctx)
	defer ui.destroy(&ctx)

	file := `
; a comment
[loom]
version = 0.1
theme = loom_light
unknown_key = 12

[wardrobe.narnia]
lion = yes

[theme.broken]
base = loom_dark
accent = not-a-colour
made_up_slot = #112233
bg = #223344

[node]
no_field_here = 4
root/library.scroll = 12 34
root/library.wobble = 9

[app]
kept = yes
`
	testing.expect(t, ui.settings_load(transmute([]byte)file), "the file loaded")
	testing.expect_value(t, ui.theme().name, "loom_light")
	testing.expect_value(t, ui.setting_string("kept"), "yes")

	broken, ok := ui.theme_by_name("broken")
	testing.expect(t, ok, "the salvageable theme survived")
	testing.expect_value(t, broken.accent, ui.LOOM_DARK.accent)
	testing.expect_value(t, broken.bg, ui.Color{34, 51, 68, 255})

	open_frame()
	restored := persisted_list(-1)
	ui.end_frame()

	testing.expect_value(t, restored.node.scroll, ui.Vec2{0, 34})
}

Dock_Stub :: struct {
	seen:  [dynamic]string,
	wrote: bool,
}

@(test)
test_a_registered_handler_owns_its_section :: proc(t: ^testing.T) {
	ctx: ui.Context
	saved(&ctx)
	defer ui.destroy(&ctx)

	stub: Dock_Stub
	stub.seen = make([dynamic]string, 0, 4, context.temp_allocator)
	defer delete(stub.seen)

	ui.settings_handler(
		{
			section = "dock",
			read = proc(name, key, value: string, user: rawptr) {
				s := (^Dock_Stub)(user)
				append(&s.seen, strings.concatenate({name, "/", key, "=", value}, context.temp_allocator))
			},
			write = proc(w: ui.Writer, user: rawptr) {
				(^Dock_Stub)(user).wrote = true
				ui.ini_write_section(w, "dock.main")
				ui.ini_write_pair(w, "ratio", "0.5")
			},
			user = &stub,
		},
	)

	file := `
[dock.main]
ratio = 0.5
active = 1
`
	testing.expect(t, ui.settings_load(transmute([]byte)file), "the file loaded")
	testing.expect_value(t, len(stub.seen), 2)
	testing.expect_value(t, stub.seen[0], "main/ratio=0.5")
	testing.expect_value(t, stub.seen[1], "main/active=1")

	text := ui.settings_save_string(context.temp_allocator)
	testing.expect(t, stub.wrote, "the handler was asked to write")
	testing.expect(t, strings.contains(text, "[dock.main]"), "the handler section is in the file")
}

@(test)
test_the_file_wrappers_round_trip :: proc(t: ^testing.T) {
	path := "loom_settings_test.ini"
	os.remove(path)
	defer os.remove(path)

	a: ui.Context
	saved(&a)

	testing.expect(t, !ui.settings_load_file(path), "a missing file reports nothing loaded")
	ui.set_setting("volume", f32(0.5))
	ui.set_theme(ui.LOOM_LIGHT)

	open_frame()
	persisted_list(90)
	ui.end_frame()

	testing.expect(t, ui.settings_save_file(path), "the file was written")
	expected := ui.settings_save_string(context.temp_allocator)
	ui.destroy(&a)

	on_disk, read_ok := os.read_entire_file_from_path(path, context.temp_allocator)
	testing.expect(t, read_ok == nil, "the file is readable")
	testing.expect_value(t, string(on_disk), expected)
	testing.expect(t, !os.exists(strings.concatenate({path, ".tmp"}, context.temp_allocator)), "the staging file is gone")

	b: ui.Context
	saved(&b)
	defer ui.destroy(&b)

	testing.expect(t, ui.settings_load_file(path), "the file loaded")
	testing.expect_value(t, ui.theme().name, "loom_light")
	testing.expect_value(t, ui.setting_f32("volume"), f32(0.5))

	open_frame()
	restored := persisted_list(-1)
	ui.end_frame()

	testing.expect_value(t, restored.node.scroll.y, f32(90))
}

@(test)
test_auto_save_waits_for_the_rate :: proc(t: ^testing.T) {
	path := "loom_autosave_test.ini"
	os.remove(path)
	defer os.remove(path)

	ctx: ui.Context
	ui.init(&ctx, ui.Config{backend = ui.noop_backend(), settings_rate = 1})
	defer ui.destroy(&ctx)

	testing.expect(t, !ui.settings_auto_save(path), "a clean context writes nothing")
	ui.set_setting("dirty", true)

	for _ in 0 ..< 30 {
		open_frame()
		ui.end_frame()
		testing.expect(t, !ui.settings_auto_save(path), "half a second is too soon")
	}
	testing.expect(t, !os.exists(path), "no file yet")

	for _ in 0 ..< 31 {
		open_frame()
		ui.end_frame()
		if ui.settings_auto_save(path) {
			break
		}
	}
	testing.expect(t, os.exists(path), "the rate elapsed and the file was written")
	testing.expect(t, !ui.settings_is_dirty(), "the auto save cleared the dirty flag")
}

@(test)
test_persist_open_round_trips :: proc(t: ^testing.T) {
	a: ui.Context
	saved(&a)

	open_frame()
	ui.begin({key = "sidebar", flags = {.Persist}})
	ui.persist().open = true
	ui.end()
	ui.end_frame()

	text := ui.settings_save_string(context.temp_allocator)
	ui.destroy(&a)

	testing.expect(t, strings.contains(text, "sidebar.open = true"), "the open flag is written")

	b: ui.Context
	saved(&b)
	defer ui.destroy(&b)

	testing.expect(t, ui.settings_load(transmute([]byte)text), "the file loaded")

	open_frame()
	ui.begin({key = "sidebar", flags = {.Persist}})
	p := ui.persist()
	ui.end()
	ui.end_frame()

	testing.expect(t, p.open, "the open flag came back")
}
