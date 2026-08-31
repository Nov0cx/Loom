package ui_dx11

import "base:runtime"
import win "core:sys/windows"
import ui "../../loom"

CLASS_NAME :: "loom_dx11_window"
ERROR_CLASS_ALREADY_EXISTS :: 1410

enable_dpi_awareness :: proc() {
	if win.SetProcessDpiAwarenessContext(win.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) {
		return
	}
	win.SetProcessDPIAware()
}

@(private)
register_class :: proc(b: ^Backend) -> bool {
	if b.class != 0 {
		return true
	}
	b.hinst = win.HINSTANCE(win.GetModuleHandleW(nil))

	wc := win.WNDCLASSEXW {
		cbSize        = size_of(win.WNDCLASSEXW),
		style         = win.CS_HREDRAW | win.CS_VREDRAW | win.CS_OWNDC,
		lpfnWndProc   = win.DefWindowProcW,
		hInstance     = b.hinst,
		hCursor       = nil,
		lpszClassName = win.utf8_to_wstring(CLASS_NAME),
	}
	b.class = win.RegisterClassExW(&wc)
	if b.class == 0 && win.GetLastError() == ERROR_CLASS_ALREADY_EXISTS {
		b.class = 1
	}
	return b.class != 0
}

create_window :: proc(b: ^Backend, title: string, w, h: int) -> win.HWND {
	if !register_class(b) {
		return nil
	}

	style := win.WS_OVERLAPPEDWINDOW | win.WS_CLIPCHILDREN
	r := win.RECT{0, 0, i32(w), i32(h)}
	win.AdjustWindowRect(&r, style, false)

	return win.CreateWindowExW(
		0,
		win.utf8_to_wstring(CLASS_NAME),
		win.utf8_to_wstring(title),
		style,
		win.CW_USEDEFAULT,
		win.CW_USEDEFAULT,
		r.right - r.left,
		r.bottom - r.top,
		nil,
		nil,
		b.hinst,
		nil,
	)
}

@(private)
create_viewport_window :: proc(b: ^Backend, title: string, rect: ui.Rect) -> win.HWND {
	if !register_class(b) {
		return nil
	}

	style := win.WS_OVERLAPPEDWINDOW | win.WS_CLIPCHILDREN
	w := i32(max(rect.w, 64))
	h := i32(max(rect.h, 64))
	r := win.RECT{0, 0, w, h}
	win.AdjustWindowRect(&r, style, false)

	return win.CreateWindowExW(
		win.WS_EX_TOOLWINDOW,
		win.utf8_to_wstring(CLASS_NAME),
		win.utf8_to_wstring(title),
		style,
		i32(rect.x),
		i32(rect.y),
		r.right - r.left,
		r.bottom - r.top,
		nil,
		nil,
		b.hinst,
		nil,
	)
}

@(private)
client_size :: proc(hwnd: win.HWND) -> (int, int) {
	if hwnd == nil {
		return 0, 0
	}
	r: win.RECT
	if !win.GetClientRect(hwnd, &r) {
		return 0, 0
	}
	return int(r.right - r.left), int(r.bottom - r.top)
}

@(private)
window_dpi :: proc(b: ^Backend, hwnd: win.HWND) -> f32 {
	if b.opts.dpi > 0 {
		return b.opts.dpi
	}
	d := win.GetDpiForWindow(hwnd)
	if d == 0 {
		return 1
	}
	return f32(d) / 96
}

@(private)
state_of :: proc "contextless" (hwnd: win.HWND) -> ^Win_State {
	return (^Win_State)(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA)))
}

@(private)
adopt_window :: proc(b: ^Backend, hwnd: win.HWND) -> ^Win_State {
	if w, ok := b.wins[hwnd]; ok {
		return w
	}

	w := new(Win_State)
	w.hwnd = hwnd
	w.back = b
	w.dpi = window_dpi(b, hwnd)
	w.prev = win.WNDPROC(rawptr(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_WNDPROC))))

	win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(w)))
	win.SetWindowLongPtrW(hwnd, win.GWLP_WNDPROC, win.LONG_PTR(uintptr(rawptr(ui_wndproc))))

	b.wins[hwnd] = w
	return w
}

@(private)
release_window :: proc(b: ^Backend, hwnd: win.HWND) {
	w, ok := b.wins[hwnd]
	if !ok {
		return
	}
	if w.prev != nil {
		win.SetWindowLongPtrW(hwnd, win.GWLP_WNDPROC, win.LONG_PTR(uintptr(rawptr(w.prev))))
	}
	win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, 0)
	delete_key(&b.wins, hwnd)
	free(w)
}

@(private)
ui_wndproc :: proc "system" (
	hwnd: win.HWND,
	msg: win.UINT,
	wp: win.WPARAM,
	lp: win.LPARAM,
) -> win.LRESULT {
	w := state_of(hwnd)
	if w == nil || w.back == nil {
		return win.DefWindowProcW(hwnd, msg, wp, lp)
	}
	context = runtime.default_context()

	res, handled := handle_message(w, msg, wp, lp)
	if handled {
		return res
	}
	if w.prev != nil {
		return win.CallWindowProcW(w.prev, hwnd, msg, wp, lp)
	}
	return win.DefWindowProcW(hwnd, msg, wp, lp)
}

should_close :: proc(b: ^Backend) -> bool {
	w, ok := b.wins[b.main.hwnd]
	return ok && w.closed
}
