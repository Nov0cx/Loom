package ui_sokol

import "core:unicode/utf8"
import sapp "../../third_party/sokol/sokol/app"
import ui "../../loom"

Win_State :: struct {
	keys_down:      ui.Key_Set,
	keys_pressed:   ui.Key_Set,
	mods:           ui.Mod_Set,
	mouse_down:     ui.Mouse_Set,
	mouse_pressed:  ui.Mouse_Set,
	mouse_released: ui.Mouse_Set,
	wheel:          ui.Vec2,
	mouse:          ui.Vec2,
	text_buf:       [64]byte,
	text_out:       [64]byte,
	text_len:       int,
	inside:         bool,
}

@(rodata)
KEYS := [?]struct {
	sk: sapp.Keycode,
	uk: ui.Key,
}{
	{.TAB, .Tab},
	{.LEFT, .Left},
	{.RIGHT, .Right},
	{.UP, .Up},
	{.DOWN, .Down},
	{.HOME, .Home},
	{.END, .End},
	{.PAGE_UP, .Page_Up},
	{.PAGE_DOWN, .Page_Down},
	{.BACKSPACE, .Backspace},
	{.DELETE, .Delete},
	{.ENTER, .Enter},
	{.KP_ENTER, .Enter},
	{.ESCAPE, .Escape},
	{.SPACE, .Space},
	{.A, .A},
	{.C, .C},
	{.V, .V},
	{.X, .X},
	{.Y, .Y},
	{.Z, .Z},
}

@(private)
key_of :: proc "contextless" (sk: sapp.Keycode) -> ui.Key {
	for k in KEYS {
		if k.sk == sk {
			return k.uk
		}
	}
	return .None
}

@(private)
mods_of :: proc "contextless" (m: u32) -> ui.Mod_Set {
	out: ui.Mod_Set
	if m & sapp.MODIFIER_CTRL != 0 {
		out += {.Ctrl}
	}
	if m & sapp.MODIFIER_SHIFT != 0 {
		out += {.Shift}
	}
	if m & sapp.MODIFIER_ALT != 0 {
		out += {.Alt}
	}
	if m & sapp.MODIFIER_SUPER != 0 {
		out += {.Super}
	}
	return out
}

@(private)
button_of :: proc "contextless" (sb: sapp.Mousebutton) -> (ui.Mouse_Button, bool) {
	switch sb {
	case .LEFT:
		return .Left, true
	case .RIGHT:
		return .Right, true
	case .MIDDLE:
		return .Middle, true
	case .INVALID:
		return .Left, false
	}
	return .Left, false
}

handle_event :: proc(b: ^Backend, e: ^sapp.Event) {
	w := &b.win
	w.mods = mods_of(e.modifiers)

	switch e.type {
	case .KEY_DOWN:
		if k := key_of(e.key_code); k != .None {
			if !e.key_repeat {
				w.keys_down += {k}
			}
			w.keys_pressed += {k}
		}

	case .KEY_UP:
		if k := key_of(e.key_code); k != .None {
			w.keys_down -= {k}
		}

	case .CHAR:
		r := rune(e.char_code)
		if r < 0x20 || r == 0x7F {
			return
		}
		bytes, n := utf8.encode_rune(r)
		if w.text_len + n > len(w.text_buf) {
			return
		}
		copy(w.text_buf[w.text_len:], bytes[:n])
		w.text_len += n

	case .MOUSE_DOWN:
		w.mouse = {e.mouse_x, e.mouse_y}
		if mb, ok := button_of(e.mouse_button); ok {
			w.mouse_down += {mb}
			w.mouse_pressed += {mb}
		}

	case .MOUSE_UP:
		w.mouse = {e.mouse_x, e.mouse_y}
		if mb, ok := button_of(e.mouse_button); ok {
			w.mouse_down -= {mb}
			w.mouse_released += {mb}
		}

	case .MOUSE_MOVE:
		w.mouse = {e.mouse_x, e.mouse_y}

	case .MOUSE_SCROLL:
		w.mouse = {e.mouse_x, e.mouse_y}
		w.wheel += {e.scroll_x, e.scroll_y}

	case .MOUSE_ENTER:
		w.mouse = {e.mouse_x, e.mouse_y}
		w.inside = true

	case .MOUSE_LEAVE:
		w.inside = false

	case .UNFOCUSED, .ICONIFIED, .SUSPENDED:
		w.keys_down = {}
		w.mouse_down = {}

	case .INVALID,
	     .TOUCHES_BEGAN,
	     .TOUCHES_MOVED,
	     .TOUCHES_ENDED,
	     .TOUCHES_CANCELLED,
	     .RESIZED,
	     .RESTORED,
	     .RESUMED,
	     .QUIT_REQUESTED,
	     .CLIPBOARD_PASTED,
	     .FILES_DROPPED,
	     .FOCUSED:
	}
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
	w := &b.win

	b.dpi = backend_dpi(b)
	scale := sapp.dpi_scale()
	if scale <= 0 {
		scale = 1
	}

	out := ui.Input {
		dt             = clamp(f32(sapp.frame_duration()), 0, 0.1),
		viewport       = {sapp.widthf() / scale, sapp.heightf() / scale},
		window_pos     = {0, 0},
		dpi            = b.dpi,
		mouse          = w.mouse / scale,
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
