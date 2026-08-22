package loom

Mouse_Button :: enum u8 {
	Left,
	Right,
	Middle,
}

Mouse_Set :: bit_set[Mouse_Button;u8]

Key :: enum u8 {
	None,
	Tab,
	Left,
	Right,
	Up,
	Down,
	Home,
	End,
	Page_Up,
	Page_Down,
	Backspace,
	Delete,
	Enter,
	Escape,
	Space,
	A,
	C,
	V,
	X,
	Y,
	Z,
}

Key_Set :: bit_set[Key;u32]

Mod :: enum u8 {
	Ctrl,
	Shift,
	Alt,
	Super,
}

Mod_Set :: bit_set[Mod;u8]

Input :: struct {
	dt:             f32,
	viewport:       Vec2,
	window_pos:     Vec2,
	dpi:            f32,
	mouse:          Vec2,
	wheel:          Vec2,
	mouse_down:     Mouse_Set,
	mouse_pressed:  Mouse_Set,
	mouse_released: Mouse_Set,
	keys_down:      Key_Set,
	keys_pressed:   Key_Set,
	mods:           Mod_Set,
	text:           string,
}

Interaction :: struct {
	id:             Id,
	node:           ^Node,
	rect:           Rect,
	state:          State_Set,
	hovered:        bool,
	pressed:        bool,
	released:       bool,
	clicked:        bool,
	right_clicked:  bool,
	middle_clicked: bool,
	double_clicked: bool,
	focused:        bool,
	changed:        bool,
	dragging:       bool,
	drag_delta:     Vec2,
	drag_start:     Vec2,
	wheel:          Vec2,
}
