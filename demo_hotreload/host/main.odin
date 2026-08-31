package main

import "core:fmt"
import "vendor:glfw"
import demo "../../demo"
import vkb "../../example_backends/vulkan_1_3"
import ui "../../loom"
import hot_link "../link"

FONT := #load("../../demo/fonts/Karla-Regular.ttf")

WIDTH :: 1280
HEIGHT :: 800
POLL_INTERVAL :: 0.25
SETTINGS :: "loom_demo_hot.ini"

main :: proc() {
	if !glfw.Init() {
		fmt.eprintln("hot: glfw failed to initialise")
		return
	}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	win := glfw.CreateWindow(WIDTH, HEIGHT, "Loom — hot reload", nil, nil)
	if win == nil {
		fmt.eprintln("hot: could not create a window")
		return
	}
	defer glfw.DestroyWindow(win)

	b: vkb.Backend
	backend, ok := vkb.init(&b, win)
	if !ok {
		fmt.eprintfln("hot: %s", b.err)
		vkb.destroy(&b)
		return
	}
	defer vkb.destroy(&b)

	font := vkb.load_face(&b, FONT)

	ctx: ui.Context
	ui.init(
		&ctx,
		{
			backend = backend,
			theme = ui.LOOM_DARK,
			root = {font = font, font_size = 14, line_height = 1.4},
		},
	)
	ui.settings_load_file(SETTINGS)

	app: demo.App
	demo.init_app(&app)
	defer demo.destroy_app(&app)

	l := hot_link.Link {
		odin_ctx   = context,
		ui_globals = ui.get_globals(),
		ui_ctx     = &ctx,
		app        = &app,
	}

	w: Watch
	watch_init(&w)
	poll_reload(&w, &l)
	if w.frame == nil {
		fmt.eprintfln("hot: %s is not next to the executable, build it first", PANELS)
	}

	for !glfw.WindowShouldClose(win) {
		poll_reload(&w, &l)
		glfw.PollEvents()

		input := vkb.poll_input(&b)

		ui.begin_frame(input)
		if w.frame != nil {
			w.frame(&l)
		}
		list := ui.end_frame()

		vkb.set_clear_color(&b, ui.theme().bg)
		vkb.render(&b, list)
		vkb.render_viewports(&b, ui.end_frame_viewports())

		ui.settings_auto_save(SETTINGS)

		if !ui.animating() {
			glfw.WaitEventsTimeout(POLL_INTERVAL)
		}
	}

	ui.settings_save_file(SETTINGS)
	ui.destroy(&ctx)
	watch_destroy(&w)
}
