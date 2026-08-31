package ui_dx11

import win "core:sys/windows"
import ui "../../loom"

Vp :: struct {
	hwnd:   win.HWND,
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
target_of :: proc(b: ^Backend, hwnd: win.HWND) -> ^Target {
	if b.main.hwnd == hwnd {
		return &b.main
	}
	for _, v in b.viewports {
		if v.hwnd == hwnd {
			return &v.target
		}
	}
	return nil
}

@(private)
vp_of :: proc(b: ^Backend, h: ui.Viewport_Handle) -> ^Vp {
	v, ok := b.viewports[h]
	return ok ? v : nil
}

@(private)
vp_create :: proc(title: string, rect: ui.Rect, user: rawptr) -> ui.Viewport_Handle {
	b := (^Backend)(user)

	hwnd := create_viewport_window(b, title, rect)
	if hwnd == nil {
		return 0
	}

	v := new(Vp)
	v.hwnd = hwnd
	if !make_swapchain(b, &v.target, hwnd) {
		destroy_target(b, &v.target)
		free(v)
		win.DestroyWindow(hwnd)
		return 0
	}

	adopt_window(b, hwnd)
	win.ShowWindow(hwnd, win.SW_SHOWNA)

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

	destroy_target(b, &v.target)
	release_window(b, v.hwnd)
	win.DestroyWindow(v.hwnd)
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

	style := win.WS_OVERLAPPEDWINDOW | win.WS_CLIPCHILDREN
	r := win.RECT{0, 0, i32(max(rect.w, 64)), i32(max(rect.h, 64))}
	win.AdjustWindowRect(&r, style, false)

	win.SetWindowPos(
		v.hwnd,
		nil,
		i32(rect.x) + r.left,
		i32(rect.y) + r.top,
		r.right - r.left,
		r.bottom - r.top,
		win.SWP_NOZORDER | win.SWP_NOACTIVATE,
	)
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

	w := adopt_window(b, v.hwnd)

	origin := client_origin(v.hwnd)
	cw, ch := client_size(v.hwnd)

	cursor: win.POINT
	win.GetCursorPos(&cursor)

	ev := ui.Viewport_Events {
		mouse          = {f32(cursor.x), f32(cursor.y)},
		wheel          = w.wheel,
		mouse_down     = w.mouse_down,
		mouse_pressed  = w.mouse_pressed,
		mouse_released = w.mouse_released,
		keys_down      = w.keys_down,
		keys_pressed   = w.keys_pressed,
		mods           = current_mods(),
		text           = take_text(w),
		rect           = {origin.x, origin.y, f32(cw), f32(ch)},
		focused        = win.GetForegroundWindow() == v.hwnd,
		has_mouse      = win.WindowFromPoint(cursor) == v.hwnd,
		closed         = w.closed,
	}

	end_poll(w)
	return ev
}
