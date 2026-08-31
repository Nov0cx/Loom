package ui_dx11

import "core:unicode/utf8"
import win "core:sys/windows"
import ui "../../loom"

Win_State :: struct {
	hwnd:           win.HWND,
	back:           ^Backend,
	prev:           win.WNDPROC,
	keys_down:      ui.Key_Set,
	keys_pressed:   ui.Key_Set,
	mouse_down:     ui.Mouse_Set,
	mouse_pressed:  ui.Mouse_Set,
	mouse_released: ui.Mouse_Set,
	wheel:          ui.Vec2,
	text_buf:       [64]byte,
	text_out:       [64]byte,
	text_len:       int,
	surrogate:      u16,
	inside:         bool,
	tracking:       bool,
	captured:       bool,
	closed:         bool,
	dpi:            f32,
}

@(rodata)
KEYS := [?]struct {
	vk: u32,
	uk: ui.Key,
}{
	{win.VK_TAB, .Tab},
	{win.VK_LEFT, .Left},
	{win.VK_RIGHT, .Right},
	{win.VK_UP, .Up},
	{win.VK_DOWN, .Down},
	{win.VK_HOME, .Home},
	{win.VK_END, .End},
	{win.VK_PRIOR, .Page_Up},
	{win.VK_NEXT, .Page_Down},
	{win.VK_BACK, .Backspace},
	{win.VK_DELETE, .Delete},
	{win.VK_RETURN, .Enter},
	{win.VK_ESCAPE, .Escape},
	{win.VK_SPACE, .Space},
	{'A', .A},
	{'C', .C},
	{'V', .V},
	{'X', .X},
	{'Y', .Y},
	{'Z', .Z},
}

@(private)
key_of :: proc "contextless" (vk: u32) -> ui.Key {
	for k in KEYS {
		if k.vk == vk {
			return k.uk
		}
	}
	return .None
}

@(private)
held :: proc "contextless" (vk: i32) -> bool {
	return win.GetKeyState(vk) < 0
}

@(private)
current_mods :: proc "contextless" () -> ui.Mod_Set {
	out: ui.Mod_Set
	if held(win.VK_CONTROL) {
		out += {.Ctrl}
	}
	if held(win.VK_SHIFT) {
		out += {.Shift}
	}
	if held(win.VK_MENU) {
		out += {.Alt}
	}
	if held(win.VK_LWIN) || held(win.VK_RWIN) {
		out += {.Super}
	}
	return out
}

@(private)
push_button :: proc(w: ^Win_State, mb: ui.Mouse_Button, down: bool) {
	if down {
		if w.mouse_down == {} && !w.captured {
			win.SetCapture(w.hwnd)
			w.captured = true
		}
		w.mouse_down += {mb}
		w.mouse_pressed += {mb}
		return
	}
	w.mouse_down -= {mb}
	w.mouse_released += {mb}
	if w.mouse_down == {} && w.captured {
		win.ReleaseCapture()
		w.captured = false
	}
}

@(private)
push_char :: proc(w: ^Win_State, unit: u16) {
	r: rune

	switch {
	case unit >= 0xD800 && unit <= 0xDBFF:
		w.surrogate = unit
		return
	case unit >= 0xDC00 && unit <= 0xDFFF:
		if w.surrogate == 0 {
			return
		}
		hi := u32(w.surrogate) - 0xD800
		lo := u32(unit) - 0xDC00
		r = rune(0x10000 + (hi << 10) + lo)
		w.surrogate = 0
	case:
		w.surrogate = 0
		r = rune(unit)
	}

	if r < 0x20 || r == 0x7F {
		return
	}

	bytes, n := utf8.encode_rune(r)
	if w.text_len + n > len(w.text_buf) {
		return
	}
	copy(w.text_buf[w.text_len:], bytes[:n])
	w.text_len += n
}

handle_message :: proc(
	w: ^Win_State,
	msg: win.UINT,
	wp: win.WPARAM,
	lp: win.LPARAM,
) -> (
	win.LRESULT,
	bool,
) {
	b := w.back

	switch msg {
	case win.WM_CLOSE:
		w.closed = true
		return 0, true

	case win.WM_DESTROY:
		w.closed = true
		if w.hwnd == b.main.hwnd {
			win.PostQuitMessage(0)
		}
		return 0, true

	case win.WM_ERASEBKGND:
		return 1, true

	case win.WM_PAINT:
		win.ValidateRect(w.hwnd, nil)
		return 0, true

	case win.WM_SIZE:
		if wp != win.SIZE_MINIMIZED {
			if t := target_of(b, w.hwnd); t != nil {
				t.resized = true
			}
		}
		return 0, true

	case win.WM_KEYDOWN, win.WM_SYSKEYDOWN:
		k := key_of(u32(wp))
		if k != .None {
			if lp & (1 << 30) == 0 {
				w.keys_down += {k}
			}
			w.keys_pressed += {k}
		}
		return 0, msg == win.WM_KEYDOWN

	case win.WM_KEYUP, win.WM_SYSKEYUP:
		if k := key_of(u32(wp)); k != .None {
			w.keys_down -= {k}
		}
		return 0, msg == win.WM_KEYUP

	case win.WM_CHAR:
		push_char(w, u16(wp))
		return 0, true

	case win.WM_MOUSEMOVE:
		w.inside = true
		if !w.tracking {
			tme := win.TRACKMOUSEEVENT {
				cbSize      = size_of(win.TRACKMOUSEEVENT),
				dwFlags     = win.TME_LEAVE,
				hwndTrack   = w.hwnd,
				dwHoverTime = 0,
			}
			win.TrackMouseEvent(&tme)
			w.tracking = true
		}
		return 0, true

	case win.WM_MOUSELEAVE:
		w.inside = false
		w.tracking = false
		return 0, true

	case win.WM_LBUTTONDOWN:
		push_button(w, .Left, true)
		return 0, true
	case win.WM_LBUTTONUP:
		push_button(w, .Left, false)
		return 0, true
	case win.WM_RBUTTONDOWN:
		push_button(w, .Right, true)
		return 0, true
	case win.WM_RBUTTONUP:
		push_button(w, .Right, false)
		return 0, true
	case win.WM_MBUTTONDOWN:
		push_button(w, .Middle, true)
		return 0, true
	case win.WM_MBUTTONUP:
		push_button(w, .Middle, false)
		return 0, true

	case win.WM_MOUSEWHEEL:
		w.wheel.y += f32(i16(u16(wp >> 16))) / win.WHEEL_DELTA
		return 0, true

	case win.WM_MOUSEHWHEEL:
		w.wheel.x += f32(i16(u16(wp >> 16))) / win.WHEEL_DELTA
		return 0, true

	case win.WM_SETCURSOR:
		if lp & 0xFFFF == win.HTCLIENT {
			win.SetCursor(b.cursors[b.cursor])
			return 1, true
		}
		return 0, false

	case win.WM_DPICHANGED:
		w.dpi = f32(u16(wp)) / 96
		if r := (^win.RECT)(uintptr(lp)); r != nil {
			win.SetWindowPos(
				w.hwnd,
				nil,
				r.left,
				r.top,
				r.right - r.left,
				r.bottom - r.top,
				win.SWP_NOZORDER | win.SWP_NOACTIVATE,
			)
		}
		return 0, true

	case win.WM_KILLFOCUS:
		w.keys_down = {}
		w.mouse_down = {}
		return 0, true

	case win.WM_ACTIVATE:
		if wp & 0xFFFF == win.WA_INACTIVE {
			w.keys_down = {}
			w.mouse_down = {}
		}
		return 0, false
	}

	return 0, false
}

@(private)
take_text :: proc(w: ^Win_State) -> string {
	if w.text_len == 0 {
		return ""
	}
	copy(w.text_out[:], w.text_buf[:w.text_len])
	n := w.text_len
	w.text_len = 0
	return string(w.text_out[:n])
}

@(private)
end_poll :: proc(w: ^Win_State) {
	w.keys_pressed = {}
	w.mouse_pressed = {}
	w.mouse_released = {}
	w.wheel = {}
}

@(private)
client_mouse :: proc(hwnd: win.HWND) -> ui.Vec2 {
	p: win.POINT
	if !win.GetCursorPos(&p) {
		return {}
	}
	win.ScreenToClient(hwnd, &p)
	return {f32(p.x), f32(p.y)}
}

poll_input :: proc(b: ^Backend) -> ui.Input {
	w := adopt_window(b, b.main.hwnd)

	now := time_now()
	dt := f32(now - b.time)
	b.time = now

	b.dpi = window_dpi(b, b.main.hwnd)
	cw, ch := client_size(b.main.hwnd)

	wr: win.RECT
	win.GetWindowRect(b.main.hwnd, &wr)

	out := ui.Input {
		dt             = clamp(dt, 0, 0.1),
		viewport       = {f32(cw) / b.dpi, f32(ch) / b.dpi},
		window_pos     = {f32(wr.left), f32(wr.top)},
		dpi            = b.dpi,
		mouse          = client_mouse(b.main.hwnd) / b.dpi,
		wheel          = w.wheel,
		mouse_down     = w.mouse_down,
		mouse_pressed  = w.mouse_pressed,
		mouse_released = w.mouse_released,
		keys_down      = w.keys_down,
		keys_pressed   = w.keys_pressed,
		mods           = current_mods(),
		text           = take_text(w),
	}

	end_poll(w)
	return out
}
