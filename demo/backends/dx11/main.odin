package main

import "core:fmt"
import win "core:sys/windows"
import dxb "../../../example_backends/dx11"
import ui "../../../loom"
import demo "../.."

FONT := #load("../../fonts/Karla-Regular.ttf")

WIDTH :: 1280
HEIGHT :: 800
IDLE_TIMEOUT_MS :: 1000
SETTINGS :: "loom_demo_dx11.ini"

main :: proc() {
	dxb.enable_dpi_awareness()

	b: dxb.Backend
	win_handle := dxb.create_window(&b, "Loom — D3D11", WIDTH, HEIGHT)
	if win_handle == nil {
		fmt.eprintln("demo: could not create a window")
		return
	}
	defer win.DestroyWindow(win_handle)

	backend, ok := dxb.init(&b, win_handle)
	if !ok {
		fmt.eprintfln("demo: %s", b.err)
		return
	}
	defer dxb.destroy(&b)

	win.ShowWindow(win_handle, win.SW_SHOW)

	font := dxb.load_face(&b, FONT)

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

	quit := false
	for !quit {
		msg: win.MSG
		for win.PeekMessageW(&msg, nil, 0, 0, win.PM_REMOVE) {
			if msg.message == win.WM_QUIT {
				quit = true
			}
			win.TranslateMessage(&msg)
			win.DispatchMessageW(&msg)
		}
		if dxb.should_close(&b) {
			quit = true
		}

		input := dxb.poll_input(&b)
		list := demo.frame(&app, input)

		dxb.set_clear_color(&b, ui.theme().bg)
		dxb.render(&b, list)
		dxb.render_viewports(&b, ui.end_frame_viewports())

		ui.settings_auto_save(SETTINGS)

		if !quit && !ui.animating() {
			win.MsgWaitForMultipleObjects(0, nil, false, IDLE_TIMEOUT_MS, win.QS_ALLINPUT)
		}
	}

	ui.settings_save_file(SETTINGS)
}
