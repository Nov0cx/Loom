package ui_opengl

import "base:runtime"
import "core:c"
import "core:unicode/utf8"
import "vendor:glfw"
import ui "../../loom"

@(rodata)
KEYS := [?]struct {
	gk: c.int,
	uk: ui.Key,
}{
	{glfw.KEY_TAB, .Tab},
	{glfw.KEY_LEFT, .Left},
	{glfw.KEY_RIGHT, .Right},
	{glfw.KEY_UP, .Up},
	{glfw.KEY_DOWN, .Down},
	{glfw.KEY_HOME, .Home},
	{glfw.KEY_END, .End},
	{glfw.KEY_PAGE_UP, .Page_Up},
	{glfw.KEY_PAGE_DOWN, .Page_Down},
	{glfw.KEY_BACKSPACE, .Backspace},
	{glfw.KEY_DELETE, .Delete},
	{glfw.KEY_ENTER, .Enter},
	{glfw.KEY_KP_ENTER, .Enter},
	{glfw.KEY_ESCAPE, .Escape},
	{glfw.KEY_SPACE, .Space},
	{glfw.KEY_A, .A},
	{glfw.KEY_C, .C},
	{glfw.KEY_V, .V},
	{glfw.KEY_X, .X},
	{glfw.KEY_Y, .Y},
	{glfw.KEY_Z, .Z},
}

@(private)
key_of :: proc "contextless" (gk: c.int) -> ui.Key {
	for k in KEYS {
		if k.gk == gk {
			return k.uk
		}
	}
	return .None
}

@(private)
mods_of :: proc "contextless" (m: c.int) -> ui.Mod_Set {
	out: ui.Mod_Set
	if m & glfw.MOD_CONTROL != 0 {
		out += {.Ctrl}
	}
	if m & glfw.MOD_SHIFT != 0 {
		out += {.Shift}
	}
	if m & glfw.MOD_ALT != 0 {
		out += {.Alt}
	}
	if m & glfw.MOD_SUPER != 0 {
		out += {.Super}
	}
	return out
}

@(private)
button_of :: proc "contextless" (gb: c.int) -> (ui.Mouse_Button, bool) {
	switch gb {
	case glfw.MOUSE_BUTTON_LEFT:
		return .Left, true
	case glfw.MOUSE_BUTTON_RIGHT:
		return .Right, true
	case glfw.MOUSE_BUTTON_MIDDLE:
		return .Middle, true
	}
	return .Left, false
}

@(private)
win_state :: proc(b: ^Backend, win: glfw.WindowHandle) -> ^Win_State {
	if w, ok := b.wins[win]; ok {
		return w
	}
	w := new(Win_State)
	b.wins[win] = w
	return w
}

@(private)
adopt_window :: proc(b: ^Backend, win: glfw.WindowHandle) {
	win_state(b, win)
	glfw.SetWindowUserPointer(win, b)
	glfw.SetKeyCallback(win, key_cb)
	glfw.SetCharCallback(win, char_cb)
	glfw.SetScrollCallback(win, scroll_cb)
	glfw.SetMouseButtonCallback(win, button_cb)
	glfw.SetCursorEnterCallback(win, enter_cb)
}

@(private)
backend_of :: proc "contextless" (win: glfw.WindowHandle) -> ^Backend {
	return (^Backend)(glfw.GetWindowUserPointer(win))
}

@(private)
key_cb :: proc "c" (win: glfw.WindowHandle, key, scancode, action, mods: c.int) {
	context = runtime.default_context()
	b := backend_of(win)
	if b == nil {
		return
	}
	w := win_state(b, win)
	w.mods = mods_of(mods)

	k := key_of(key)
	if k == .None {
		return
	}
	switch action {
	case glfw.PRESS:
		w.keys_down += {k}
		w.keys_pressed += {k}
	case glfw.REPEAT:
		w.keys_pressed += {k}
	case glfw.RELEASE:
		w.keys_down -= {k}
	}
}

@(private)
char_cb :: proc "c" (win: glfw.WindowHandle, r: rune) {
	context = runtime.default_context()
	b := backend_of(win)
	if b == nil {
		return
	}
	w := win_state(b, win)
	bytes, n := utf8.encode_rune(r)
	if w.text_len + n > len(w.text_buf) {
		return
	}
	copy(w.text_buf[w.text_len:], bytes[:n])
	w.text_len += n
}

@(private)
scroll_cb :: proc "c" (win: glfw.WindowHandle, dx, dy: f64) {
	context = runtime.default_context()
	b := backend_of(win)
	if b == nil {
		return
	}
	w := win_state(b, win)
	w.wheel += {f32(dx), f32(dy)}
}

@(private)
button_cb :: proc "c" (win: glfw.WindowHandle, button, action, mods: c.int) {
	context = runtime.default_context()
	b := backend_of(win)
	if b == nil {
		return
	}
	w := win_state(b, win)
	w.mods = mods_of(mods)

	mb, ok := button_of(button)
	if !ok {
		return
	}
	if action == glfw.PRESS {
		w.mouse_down += {mb}
		w.mouse_pressed += {mb}
	} else if action == glfw.RELEASE {
		w.mouse_down -= {mb}
		w.mouse_released += {mb}
	}
}

@(private)
enter_cb :: proc "c" (win: glfw.WindowHandle, entered: c.int) {
	context = runtime.default_context()
	b := backend_of(win)
	if b == nil {
		return
	}
	win_state(b, win).inside = entered != 0
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

poll_input :: proc(b: ^Backend) -> ui.Input {
	w := win_state(b, b.win)

	now := glfw.GetTime()
	dt := f32(now - b.time)
	b.time = now

	ww, wh := glfw.GetWindowSize(b.win)
	wx, wy := glfw.GetWindowPos(b.win)
	mx, my := glfw.GetCursorPos(b.win)
	b.dpi = window_dpi(b, b.win)

	out := ui.Input {
		dt             = clamp(dt, 0, 0.1),
		viewport       = {f32(ww), f32(wh)},
		window_pos     = {f32(wx), f32(wy)},
		dpi            = b.dpi,
		mouse          = {f32(mx), f32(my)},
		wheel          = w.wheel,
		mouse_down     = w.mouse_down,
		mouse_pressed  = w.mouse_pressed,
		mouse_released = w.mouse_released,
		keys_down      = w.keys_down,
		keys_pressed   = w.keys_pressed,
		mods           = w.mods,
		text           = take_text(w),
	}

	end_poll(w)
	return out
}
