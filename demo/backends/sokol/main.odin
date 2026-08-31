package main

import "base:runtime"
import "core:fmt"
import skb "../../../example_backends/sokol"
import ui "../../../loom"
import sapp "../../../third_party/sokol/sokol/app"
import sg "../../../third_party/sokol/sokol/gfx"
import sglue "../../../third_party/sokol/sokol/glue"
import slog "../../../third_party/sokol/sokol/log"
import demo "../.."

FONT := #load("../../fonts/Karla-Regular.ttf")

WIDTH :: 1280
HEIGHT :: 800
SETTINGS :: "loom_demo_sokol.ini"

State :: struct {
	b:    skb.Backend,
	ctx:  ui.Context,
	app:  demo.App,
	font: ui.Font,
	ok:   bool,
}

init_cb :: proc "c" (u: rawptr) {
	context = runtime.default_context()
	s := (^State)(u)

	sg.setup({environment = sglue.environment(), logger = {func = slog.func}})

	backend, ok := skb.init(&s.b)
	s.ok = ok
	if !ok {
		fmt.eprintfln("demo: %s", s.b.err)
		sapp.request_quit()
		return
	}

	s.font = skb.load_face(&s.b, FONT)

	ui.init(
		&s.ctx,
		{
			backend = backend,
			theme = ui.LOOM_DARK,
			root = {font = s.font, font_size = 14, line_height = 1.4},
		},
	)
	ui.settings_load_file(SETTINGS)

	demo.init_app(&s.app)
}

frame_cb :: proc "c" (u: rawptr) {
	context = runtime.default_context()
	s := (^State)(u)
	if !s.ok {
		return
	}

	input := skb.poll_input(&s.b)
	list := demo.frame(&s.app, input)

	skb.set_clear_color(&s.b, ui.theme().bg)
	skb.render(&s.b, list)

	ui.settings_auto_save(SETTINGS)
}

event_cb :: proc "c" (e: ^sapp.Event, u: rawptr) {
	context = runtime.default_context()
	s := (^State)(u)
	if !s.ok {
		return
	}
	skb.handle_event(&s.b, e)
}

cleanup_cb :: proc "c" (u: rawptr) {
	context = runtime.default_context()
	s := (^State)(u)

	if s.ok {
		ui.settings_save_file(SETTINGS)
		demo.destroy_app(&s.app)
		ui.destroy(&s.ctx)
		skb.destroy(&s.b)
	}
	sg.shutdown()
}

main :: proc() {
	s: State
	sapp.run(
		{
			user_data = &s,
			init_userdata_cb = init_cb,
			frame_userdata_cb = frame_cb,
			event_userdata_cb = event_cb,
			cleanup_userdata_cb = cleanup_cb,
			width = WIDTH,
			height = HEIGHT,
			sample_count = 4,
			high_dpi = true,
			window_title = "Loom — sokol",
			enable_clipboard = true,
			clipboard_size = 8192,
			logger = {func = slog.func},
		},
	)
}
