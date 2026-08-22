package tests

import "core:testing"
import ui "../loom"

themed :: proc(ctx: ^ui.Context, theme: ui.Theme = {}) {
	ui.init(ctx, ui.Config{backend = fake_backend(), theme = theme, root = {font_size = 16}})
}

text_color :: proc(list: ui.Draw_List) -> (ui.Color, bool) {
	for cmd in list.cmds {
		if c, ok := cmd.(ui.Cmd_Text); ok {
			return c.color, true
		}
	}
	return {}, false
}

@(test)
test_zero_config_resolves_to_the_default_theme :: proc(t: ^testing.T) {
	ctx: ui.Context
	themed(&ctx)
	defer ui.destroy(&ctx)

	testing.expect_value(t, ui.theme().name, "loom_dark")
	testing.expect_value(t, ui.theme()^, ui.LOOM_DARK)
}

@(test)
test_config_theme_wins_over_the_default :: proc(t: ^testing.T) {
	ctx: ui.Context
	themed(&ctx, ui.LOOM_LIGHT)
	defer ui.destroy(&ctx)

	testing.expect_value(t, ui.theme().name, "loom_light")
}

@(test)
test_theme_by_name_finds_the_builtins :: proc(t: ^testing.T) {
	ctx: ui.Context
	themed(&ctx)
	defer ui.destroy(&ctx)

	dark, dark_ok := ui.theme_by_name("loom_dark")
	testing.expect(t, dark_ok, "loom_dark is a builtin")
	testing.expect_value(t, dark, ui.LOOM_DARK)

	light, light_ok := ui.theme_by_name("loom_light")
	testing.expect(t, light_ok, "loom_light is a builtin")
	testing.expect_value(t, light, ui.LOOM_LIGHT)

	_, bad := ui.theme_by_name("nope")
	testing.expect(t, !bad, "an unknown name reports false")
}

@(test)
test_registered_theme_round_trips_by_name :: proc(t: ^testing.T) {
	ctx: ui.Context
	themed(&ctx)
	defer ui.destroy(&ctx)

	mine := ui.LOOM_DARK
	mine.name = "mine"
	mine.accent = RED
	ui.register_theme(mine)

	testing.expect(t, ui.set_theme_name("mine"), "the registered theme is selectable")
	testing.expect_value(t, ui.theme().accent, RED)
	testing.expect(t, !ui.set_theme_name("missing"), "an unknown name changes nothing")
	testing.expect_value(t, ui.theme().accent, RED)
}

@(test)
test_theme_names_are_sorted_and_deduplicated :: proc(t: ^testing.T) {
	ctx: ui.Context
	themed(&ctx)
	defer ui.destroy(&ctx)

	mine := ui.LOOM_DARK
	mine.name = "aardvark"
	ui.register_theme(mine)

	names := ui.theme_names(context.temp_allocator)
	testing.expect_value(t, len(names), 3)
	testing.expect_value(t, names[0], "aardvark")
	testing.expect_value(t, names[1], "loom_dark")
	testing.expect_value(t, names[2], "loom_light")
}

@(test)
test_unset_text_colour_comes_from_the_theme :: proc(t: ^testing.T) {
	ctx: ui.Context
	themed(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.leaf({key = "label", text = "hello"})
	dark_list := ui.end_frame()
	dark, dark_ok := text_color(dark_list)
	testing.expect(t, dark_ok, "the frame emitted text")
	testing.expect_value(t, dark, ui.LOOM_DARK.text)

	ui.set_theme(ui.LOOM_LIGHT)

	open_frame()
	ui.leaf({key = "label", text = "hello"})
	light_list := ui.end_frame()
	light, light_ok := text_color(light_list)
	testing.expect(t, light_ok, "the frame emitted text")
	testing.expect_value(t, light, ui.LOOM_LIGHT.text)
}

@(test)
test_explicit_colour_still_beats_the_theme :: proc(t: ^testing.T) {
	ctx: ui.Context
	themed(&ctx)
	defer ui.destroy(&ctx)

	open_frame()
	ui.leaf({key = "label", text = "hello", props = {color = RED}})
	list := ui.end_frame()

	c, ok := text_color(list)
	testing.expect(t, ok, "the frame emitted text")
	testing.expect_value(t, c, RED)
}

@(test)
test_setting_a_theme_marks_the_settings_dirty :: proc(t: ^testing.T) {
	ctx: ui.Context
	themed(&ctx)
	defer ui.destroy(&ctx)

	testing.expect(t, !ui.settings_is_dirty(), "a fresh context is clean")
	ui.set_theme(ui.LOOM_DARK)
	testing.expect(t, !ui.settings_is_dirty(), "setting the same theme changes nothing")
	ui.set_theme(ui.LOOM_LIGHT)
	testing.expect(t, ui.settings_is_dirty(), "a real change marks the settings dirty")
}
