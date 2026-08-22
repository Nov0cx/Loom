package main

import "core:fmt"
import gl "vendor:OpenGL"
import "vendor:glfw"
import glb "../../../example_backends/opengl"
import ui "../../../loom"
import demo "../.."

FONT := #load("../../fonts/Karla-Regular.ttf")

WIDTH :: 1280
HEIGHT :: 800
IDLE_TIMEOUT :: 0.25
SETTINGS :: "loom_demo_opengl.ini"

main :: proc() {
	if !glfw.Init() {
		fmt.eprintln("demo: glfw failed to initialise")
		return
	}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.SAMPLES, 4)

	win := glfw.CreateWindow(WIDTH, HEIGHT, "Loom — OpenGL", nil, nil)
	if win == nil {
		fmt.eprintln("demo: could not create a window")
		return
	}
	defer glfw.DestroyWindow(win)

	glfw.MakeContextCurrent(win)
	glfw.SwapInterval(1)

	b: glb.Backend
	backend := glb.init(&b, win)
	defer glb.destroy(&b)

	font := glb.load_face(&b, FONT)

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

		input := glb.poll_input(&b)
		list := demo.frame(&app, input)

		bg := ui.theme().bg
		glb.set_clear_color(&b, bg)

		fw, fh := glfw.GetFramebufferSize(win)
		gl.Viewport(0, 0, i32(fw), i32(fh))
		gl.Disable(gl.SCISSOR_TEST)
		gl.ClearColor(f32(bg[0]) / 255, f32(bg[1]) / 255, f32(bg[2]) / 255, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		glb.render(&b, list)
		glfw.SwapBuffers(win)

		glb.render_viewports(&b, ui.end_frame_viewports())

		ui.settings_auto_save(SETTINGS)

		if !ui.animating() {
			glfw.WaitEventsTimeout(IDLE_TIMEOUT)
		}
	}

	ui.settings_save_file(SETTINGS)
}
