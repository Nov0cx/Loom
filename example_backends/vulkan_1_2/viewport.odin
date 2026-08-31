package ui_vulkan_1_2

import "core:c"
import vk "vendor:vulkan"
import "vendor:glfw"
import ui "../../loom"

Vp :: struct {
	win:    glfw.WindowHandle,
	handle: ui.Viewport_Handle,
	target: Target,
}

viewport_ops :: proc() -> ui.Viewport_Ops {
	return ui.Viewport_Ops {
		create = vp_create,
		destroy = vp_destroy,
		set_rect = vp_set_rect,
		begin = vp_begin,
		end = vp_end,
		poll = vp_poll,
	}
}

set_clear_color :: proc(b: ^Backend, col: ui.Color) {
	b.clear = col
}

render_viewports :: proc(b: ^Backend, draws: []ui.Viewport_Draw) {
	for d in draws {
		vp_begin(d.handle, b)
		render(b, d.list)
		vp_end(d.handle, b)
	}
}

@(private)
vp_of :: proc(b: ^Backend, h: ui.Viewport_Handle) -> ^Vp {
	v, ok := b.viewports[h]
	return ok ? v : nil
}

@(private)
vp_create :: proc(title: string, rect: ui.Rect, user: rawptr) -> ui.Viewport_Handle {
	b := (^Backend)(user)

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.VISIBLE, false)
	win := glfw.CreateWindow(c.int(max(rect.w, 64)), c.int(max(rect.h, 64)), cstr(title), nil, nil)
	glfw.WindowHint(glfw.VISIBLE, true)
	if win == nil {
		return 0
	}

	v := new(Vp)
	v.win = win
	if glfw.CreateWindowSurface(b.instance, win, nil, &v.target.surface) != .SUCCESS {
		free(v)
		glfw.DestroyWindow(win)
		return 0
	}

	supported: b32
	vk.GetPhysicalDeviceSurfaceSupportKHR(b.gpu, b.qfamily, v.target.surface, &supported)
	if !supported || !make_target(b, &v.target, win) {
		destroy_target(b, &v.target)
		free(v)
		glfw.DestroyWindow(win)
		return 0
	}

	glfw.SetWindowPos(win, c.int(rect.x), c.int(rect.y))
	adopt_window(b, win)
	glfw.ShowWindow(win)

	b.next_vp += 1
	v.handle = ui.Viewport_Handle(b.next_vp)
	b.viewports[v.handle] = v
	return v.handle
}

@(private)
vp_destroy :: proc(h: ui.Viewport_Handle, user: rawptr) {
	b := (^Backend)(user)
	v := vp_of(b, h)
	if v == nil {
		return
	}

	vk.DeviceWaitIdle(b.device)
	destroy_target(b, &v.target)

	if w, ok := b.wins[v.win]; ok {
		free(w)
		delete_key(&b.wins, v.win)
	}
	glfw.DestroyWindow(v.win)
	delete_key(&b.viewports, h)
	free(v)

	b.target = &b.main
}

@(private)
vp_set_rect :: proc(h: ui.Viewport_Handle, rect: ui.Rect, user: rawptr) {
	b := (^Backend)(user)
	v := vp_of(b, h)
	if v == nil {
		return
	}
	glfw.SetWindowPos(v.win, c.int(rect.x), c.int(rect.y))
	glfw.SetWindowSize(v.win, c.int(max(rect.w, 64)), c.int(max(rect.h, 64)))
}

@(private)
vp_begin :: proc(h: ui.Viewport_Handle, user: rawptr) {
	b := (^Backend)(user)
	if v := vp_of(b, h); v != nil {
		b.target = &v.target
	}
}

@(private)
vp_end :: proc(h: ui.Viewport_Handle, user: rawptr) {
	b := (^Backend)(user)
	b.target = &b.main
}

@(private)
vp_poll :: proc(h: ui.Viewport_Handle, user: rawptr) -> ui.Viewport_Events {
	b := (^Backend)(user)
	v := vp_of(b, h)
	if v == nil {
		return {closed = true}
	}

	w := win_state(b, v.win)
	wx, wy := glfw.GetWindowPos(v.win)
	ww, wh := glfw.GetWindowSize(v.win)
	mx, my := glfw.GetCursorPos(v.win)

	ev := ui.Viewport_Events {
		mouse          = {f32(wx) + f32(mx), f32(wy) + f32(my)},
		wheel          = w.wheel,
		mouse_down     = w.mouse_down,
		mouse_pressed  = w.mouse_pressed,
		mouse_released = w.mouse_released,
		keys_down      = w.keys_down,
		keys_pressed   = w.keys_pressed,
		mods           = w.mods,
		text           = take_text(w),
		rect           = {f32(wx), f32(wy), f32(ww), f32(wh)},
		focused        = glfw.GetWindowAttrib(v.win, glfw.FOCUSED) != 0,
		has_mouse      = glfw.GetWindowAttrib(v.win, glfw.HOVERED) != 0,
		closed         = bool(glfw.WindowShouldClose(v.win)),
	}

	end_poll(w)
	return ev
}
