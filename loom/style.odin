package loom

Direction :: enum u8 {
	Row,
	Column,
	Row_Reverse,
	Column_Reverse,
}

Wrap :: enum u8 {
	None,
	Wrap,
	Wrap_Reverse,
}

Justify :: enum u8 {
	Start,
	Center,
	End,
	Space_Between,
	Space_Around,
	Space_Evenly,
}

Align :: enum u8 {
	Auto,
	Stretch,
	Start,
	Center,
	End,
	Baseline,
}

Position :: enum u8 {
	Flow,
	Absolute,
	Fixed,
}

Overflow :: enum u8 {
	Visible,
	Hidden,
	Scroll,
	Auto,
}

Text_Align :: enum u8 {
	Start,
	Center,
	End,
	Justify,
}

Text_Wrap :: enum u8 {
	Words,
	None,
	Chars,
	Ellipsis,
}

Cursor :: enum u8 {
	Default,
	Pointer,
	Text,
	Resize_H,
	Resize_V,
	Grab,
	Grabbing,
	Not_Allowed,
}

Stop :: struct {
	t:     f32,
	color: Color,
}

Gradient :: struct {
	kind:  enum u8 {
		Linear,
		Radial,
	},
	angle: f32,
	stops: []Stop,
}

Paint :: union {
	Color,
	Gradient,
}

Border :: struct {
	width: Edges,
	color: Color,
}

Shadow :: struct {
	offset: Vec2,
	blur:   f32,
	spread: f32,
	color:  Color,
	inset:  bool,
}

Props :: struct {
	dir:            Direction,
	wrap:           Wrap,
	justify:        Justify,
	align:          Align,
	gap:            Vec2,
	pad:            Edges,
	w, h:           Size,
	min_w, min_h:   f32,
	max_w, max_h:   f32,
	margin:         Edges,
	align_self:     Align,
	order:          i16,
	aspect:         f32,
	position:       Position,
	inset:          Edges,
	z:              i16,
	overflow:       [2]Overflow,
	bg:             Paint,
	border:         Border,
	radius:         Radius,
	shadow:         Shadow,
	opacity:        Maybe(f32),
	font:           Font,
	font_size:      f32,
	color:          Maybe(Color),
	line_height:    f32,
	letter_spacing: f32,
	text_align:     Text_Align,
	text_wrap:      Text_Wrap,
	cursor:         Cursor,
	clear:          Prop_Set,
}

Prop :: enum u8 {
	W,
	H,
	Min_W,
	Min_H,
	Max_W,
	Max_H,
	Pad,
	Margin,
	Gap,
	Inset,
	Bg,
	Border_Color,
	Border_Width,
	Radius,
	Shadow,
	Opacity,
	Color,
	Font_Size,
	Line_Height,
	Letter_Spacing,
}

Prop_Set :: bit_set[Prop;u32]

ALL_PROPS :: ~Prop_Set{}

State :: enum u8 {
	Hover,
	Active,
	Focus,
	Focus_Within,
	Disabled,
	Checked,
	Open,
	Group_Hover,
}

State_Set :: bit_set[State;u16]

Rule :: struct {
	on:    State_Set,
	props: Props,
}

Ease :: enum u8 {
	Linear,
	Out_Quad,
	In_Out_Quad,
	Out_Cubic,
	Out_Back,
	Spring,
}

Transition :: struct {
	props: Prop_Set,
	dur:   f32,
	delay: f32,
	ease:  Ease,
}
