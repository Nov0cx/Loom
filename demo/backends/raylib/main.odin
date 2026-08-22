package main

import rl "vendor:raylib"
import rlb "../../../example_backends/raylib"
import ui "../../../loom"
import demo "../.."

FONT := #load("../../fonts/Karla-Regular.ttf")

WIDTH :: 1280
HEIGHT :: 800
TARGET_FPS :: 60
SETTINGS :: "loom_demo_raylib.ini"

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT, .VSYNC_HINT})
	rl.InitWindow(WIDTH, HEIGHT, "Loom — raylib")
	defer rl.CloseWindow()

	rl.SetExitKey(.KEY_NULL)
	rl.SetTargetFPS(TARGET_FPS)

	b: rlb.Backend
	backend := rlb.init(&b)
	defer rlb.destroy(&b)

	font := rlb.load_face(&b, FONT)

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

	for !rl.WindowShouldClose() {
		input := rlb.poll_input(&b)
		list := demo.frame(&app, input)

		bg := ui.theme().bg
		rl.BeginDrawing()
		rl.ClearBackground({bg[0], bg[1], bg[2], 255})
		rlb.render(&b, list)
		rl.EndDrawing()

		ui.settings_auto_save(SETTINGS)
	}

	ui.settings_save_file(SETTINGS)
}
