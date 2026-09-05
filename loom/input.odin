package loom

Mouse_Button :: enum u8 {
	Left,
	Right,
	Middle,
}

Mouse_Set :: bit_set[Mouse_Button;u8]

// A physical key, named after the US layout position. A host that remaps to the
// user's layout reports the mapped key, so a binding follows the printed cap.
Key :: enum u8 {
	None,

	// Letters.
	A, B, C, D, E, F, G, H, I, J, K, L, M,
	N, O, P, Q, R, S, T, U, V, W, X, Y, Z,

	// The digit row.
	Num_0, Num_1, Num_2, Num_3, Num_4,
	Num_5, Num_6, Num_7, Num_8, Num_9,

	// Function keys.
	F1, F2, F3, F4, F5, F6,
	F7, F8, F9, F10, F11, F12,

	// Punctuation.
	Minus,
	Equal,
	Left_Bracket,
	Right_Bracket,
	Backslash,
	Semicolon,
	Apostrophe,
	Grave,
	Comma,
	Period,
	Slash,

	// Navigation and editing.
	Tab,
	Left,
	Right,
	Up,
	Down,
	Home,
	End,
	Page_Up,
	Page_Down,
	Insert,
	Backspace,
	Delete,
	Enter,
	Escape,
	Space,

	// Locks and system keys.
	Caps_Lock,
	Num_Lock,
	Scroll_Lock,
	Print_Screen,
	Pause,
	Menu,

	// Modifiers, with the side kept.
	Left_Shift,
	Right_Shift,
	Left_Ctrl,
	Right_Ctrl,
	Left_Alt,
	Right_Alt,
	Left_Super,
	Right_Super,

	// The keypad.
	Pad_0, Pad_1, Pad_2, Pad_3, Pad_4,
	Pad_5, Pad_6, Pad_7, Pad_8, Pad_9,
	Pad_Decimal,
	Pad_Divide,
	Pad_Multiply,
	Pad_Subtract,
	Pad_Add,
	Pad_Enter,
	Pad_Equal,
}

// The backing width follows the member count, so a key added below 128 members
// costs nothing at the call sites.
Key_Set :: bit_set[Key]

Mod :: enum u8 {
	Ctrl,
	Shift,
	Alt,
	Super,
}

Mod_Set :: bit_set[Mod;u8]

Key_Action :: enum u8 {
	Press,
	Repeat,
	Release,
}

// One entry of the ordered key stream. `consumed` is written by a reader that
// takes the event, which hides it from every later reader of the same frame.
Key_Event :: struct {
	key:      Key,
	mods:     Mod_Set,
	action:   Key_Action,
	consumed: bool,
}

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
	// The ordered key stream, with repeats and releases. A host that fills it
	// gets `keys_down` and `keys_pressed` folded in by `begin_frame`, so filling
	// only one of the two forms is enough.
	key_events:     []Key_Event,
	mods:           Mod_Set,
	text:           string,
}

Interaction :: struct {
	id:             Id,
	node:           ^Node,
	rect:           Rect,
	state:          State_Set,
	hovered:        bool,
	hover_entered:  bool,
	hover_exited:   bool,
	pressed:        bool,
	released:       bool,
	clicked:        bool,
	click_count:    int,
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
