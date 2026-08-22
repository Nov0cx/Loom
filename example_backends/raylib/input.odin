package ui_raylib

import "core:unicode/utf8"
import rl "vendor:raylib"
import ui "../../loom"

@(rodata)
KEYS := [?]struct {
	rk: rl.KeyboardKey,
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

	for k in KEYS {
		if rl.IsKeyDown(k.rk) {
			out.keys_down += {k.uk}
		}
		if rl.IsKeyPressed(k.rk) || rl.IsKeyPressedRepeat(k.rk) {
			out.keys_pressed += {k.uk}
		}
	}

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
