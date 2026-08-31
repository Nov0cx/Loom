package main

import "core:fmt"
import "vendor:glfw"
import vkb "../../../example_backends/vulkan_1_2"
import ui "../../../loom"
import demo "../.."

FONT := #load("../../fonts/Karla-Regular.ttf")

WIDTH :: 1280
HEIGHT :: 800
IDLE_TIMEOUT :: 1.0
SETTINGS :: "loom_demo_vulkan_1_2.ini"

main :: proc() {
	if !glfw.Init() {
		fmt.eprintln("demo: glfw failed to initialise")
		return
	}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	win := glfw.CreateWindow(WIDTH, HEIGHT, "Loom — Vulkan 1.2", nil, nil)
	if win == nil {
		fmt.eprintln("demo: could not create a window")
		return
	}
	defer glfw.DestroyWindow(win)

	b: vkb.Backend
	backend, ok := vkb.init(&b, win)
	if !ok {
		fmt.eprintfln("demo: %s", b.err)
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
	defer ui.destroy(&ctx)
	ui.settings_load_file(SETTINGS)

	app: demo.App
	demo.init_app(&app)
	defer demo.destroy_app(&app)

	for !glfw.WindowShouldClose(win) {
		glfw.PollEvents()

		input := vkb.poll_input(&b)
		list := demo.frame(&app, input)

		vkb.set_clear_color(&b, ui.theme().bg)
		vkb.render(&b, list)
		vkb.render_viewports(&b, ui.end_frame_viewports())

		ui.settings_auto_save(SETTINGS)

		if !ui.animating() {
			glfw.WaitEventsTimeout(IDLE_TIMEOUT)
		}
	}

	ui.settings_save_file(SETTINGS)
}
