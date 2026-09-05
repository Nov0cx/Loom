package ui_raylib

import "core:unicode/utf8"
import rl "vendor:raylib"
import ui "../../loom"

// The keypad Enter reports as Enter, which is what a form expects. Every other
// keypad key keeps its own identity.
@(rodata)
KEYS := [?]struct {
	rk: rl.KeyboardKey,
	uk: ui.Key,
}{
	{.A, .A},
	{.B, .B},
	{.C, .C},
	{.D, .D},
	{.E, .E},
	{.F, .F},
	{.G, .G},
	{.H, .H},
	{.I, .I},
	{.J, .J},
	{.K, .K},
	{.L, .L},
	{.M, .M},
	{.N, .N},
	{.O, .O},
	{.P, .P},
	{.Q, .Q},
	{.R, .R},
	{.S, .S},
	{.T, .T},
	{.U, .U},
	{.V, .V},
	{.W, .W},
	{.X, .X},
	{.Y, .Y},
	{.Z, .Z},
	{.ZERO, .Num_0},
	{.ONE, .Num_1},
	{.TWO, .Num_2},
	{.THREE, .Num_3},
	{.FOUR, .Num_4},
	{.FIVE, .Num_5},
	{.SIX, .Num_6},
	{.SEVEN, .Num_7},
	{.EIGHT, .Num_8},
	{.NINE, .Num_9},
	{.F1, .F1},
	{.F2, .F2},
	{.F3, .F3},
	{.F4, .F4},
	{.F5, .F5},
	{.F6, .F6},
	{.F7, .F7},
	{.F8, .F8},
	{.F9, .F9},
	{.F10, .F10},
	{.F11, .F11},
	{.F12, .F12},
	{.MINUS, .Minus},
	{.EQUAL, .Equal},
	{.LEFT_BRACKET, .Left_Bracket},
	{.RIGHT_BRACKET, .Right_Bracket},
	{.BACKSLASH, .Backslash},
	{.SEMICOLON, .Semicolon},
	{.APOSTROPHE, .Apostrophe},
	{.GRAVE, .Grave},
	{.COMMA, .Comma},
	{.PERIOD, .Period},
	{.SLASH, .Slash},
	{.TAB, .Tab},
	{.LEFT, .Left},
	{.RIGHT, .Right},
	{.UP, .Up},
	{.DOWN, .Down},
	{.HOME, .Home},
	{.END, .End},
	{.PAGE_UP, .Page_Up},
	{.PAGE_DOWN, .Page_Down},
	{.INSERT, .Insert},
	{.BACKSPACE, .Backspace},
	{.DELETE, .Delete},
	{.ENTER, .Enter},
	{.KP_ENTER, .Enter},
	{.ESCAPE, .Escape},
	{.SPACE, .Space},
	{.CAPS_LOCK, .Caps_Lock},
	{.NUM_LOCK, .Num_Lock},
	{.SCROLL_LOCK, .Scroll_Lock},
	{.PRINT_SCREEN, .Print_Screen},
	{.PAUSE, .Pause},
	{.KB_MENU, .Menu},
	{.LEFT_SHIFT, .Left_Shift},
	{.RIGHT_SHIFT, .Right_Shift},
	{.LEFT_CONTROL, .Left_Ctrl},
	{.RIGHT_CONTROL, .Right_Ctrl},
	{.LEFT_ALT, .Left_Alt},
	{.RIGHT_ALT, .Right_Alt},
	{.LEFT_SUPER, .Left_Super},
	{.RIGHT_SUPER, .Right_Super},
	{.KP_0, .Pad_0},
	{.KP_1, .Pad_1},
	{.KP_2, .Pad_2},
	{.KP_3, .Pad_3},
	{.KP_4, .Pad_4},
	{.KP_5, .Pad_5},
	{.KP_6, .Pad_6},
	{.KP_7, .Pad_7},
	{.KP_8, .Pad_8},
	{.KP_9, .Pad_9},
	{.KP_DECIMAL, .Pad_Decimal},
	{.KP_DIVIDE, .Pad_Divide},
	{.KP_MULTIPLY, .Pad_Multiply},
	{.KP_SUBTRACT, .Pad_Subtract},
	{.KP_ADD, .Pad_Add},
	{.KP_EQUAL, .Pad_Equal},
}

@(rodata)
BUTTONS := [?]struct {
	rb: rl.MouseButton,
	ub: ui.Mouse_Button,
}{{.LEFT, .Left}, {.RIGHT, .Right}, {.MIDDLE, .Middle}}

poll_input :: proc(b: ^Backend) -> ui.Input {
	scale := rl.GetWindowScaleDPI()
	b.dpi = b.opts.dpi > 0 ? b.opts.dpi : scale.x

	pos := rl.GetWindowPosition()
	out := ui.Input {
		dt         = rl.GetFrameTime(),
		viewport   = {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())},
		window_pos = {pos.x, pos.y},
		dpi        = b.dpi,
		mouse      = ui.Vec2(rl.GetMousePosition()),
		wheel      = ui.Vec2(rl.GetMouseWheelMoveV()),
	}

	for pair in BUTTONS {
		if rl.IsMouseButtonDown(pair.rb) {
			out.mouse_down += {pair.ub}
		}
		if rl.IsMouseButtonPressed(pair.rb) {
			out.mouse_pressed += {pair.ub}
		}
		if rl.IsMouseButtonReleased(pair.rb) {
			out.mouse_released += {pair.ub}
		}
	}

	// The modifiers come first, so every event of this frame carries them.
	if rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) {
		out.mods += {.Ctrl}
	}
	if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) {
		out.mods += {.Shift}
	}
	if rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT) {
		out.mods += {.Alt}
	}
	if rl.IsKeyDown(.LEFT_SUPER) || rl.IsKeyDown(.RIGHT_SUPER) {
		out.mods += {.Super}
	}

	clear(&b.key_evs)
	for k in KEYS {
		if rl.IsKeyDown(k.rk) {
			out.keys_down += {k.uk}
		}
		pressed := rl.IsKeyPressed(k.rk)
		repeat := rl.IsKeyPressedRepeat(k.rk)
		if pressed || repeat {
			out.keys_pressed += {k.uk}
			action: ui.Key_Action = pressed ? .Press : .Repeat
			append(&b.key_evs, ui.Key_Event{key = k.uk, mods = out.mods, action = action})
		}
		if rl.IsKeyReleased(k.rk) {
			append(&b.key_evs, ui.Key_Event{key = k.uk, mods = out.mods, action = .Release})
		}
	}
	out.key_events = b.key_evs[:]

	b.text_len = 0
	for {
		r := rl.GetCharPressed()
		if r == 0 {
			break
		}
		bytes, n := utf8.encode_rune(r)
		if b.text_len + n > len(b.text_buf) {
			break
		}
		copy(b.text_buf[b.text_len:], bytes[:n])
		b.text_len += n
	}
	out.text = string(b.text_buf[:b.text_len])

	return out
}
