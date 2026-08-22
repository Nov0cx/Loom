package loom

Cmd_Rect :: struct {
	rect:   Rect,
	paint:  Paint,
	radius: Radius,
	border: Border,
	shadow: Shadow,
}

Cmd_Text :: struct {
	pos:   Vec2,
	text:  string,
	font:  Font,
	size:  f32,
	color: Color,
}

Cmd_Image :: struct {
	rect:   Rect,
	tex:    Texture,
	uv:     Rect,
	tint:   Color,
	radius: Radius,
}

Cmd_Push_Clip :: struct {
	rect:   Rect,
	radius: Radius,
}

Cmd_Pop_Clip :: struct {}

Cmd_Custom :: struct {
	node: ^Node,
	draw: proc(node: ^Node, user: rawptr),
	user: rawptr,
}

Draw_Command :: union {
	Cmd_Rect,
	Cmd_Text,
	Cmd_Image,
	Cmd_Push_Clip,
	Cmd_Pop_Clip,
	Cmd_Custom,
}

Draw_List :: struct {
	cmds: []Draw_Command,
}
