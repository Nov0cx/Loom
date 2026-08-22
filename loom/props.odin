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
	Relative,
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

Prop_Kind :: enum u8 {
	F32,
	Vec2,
	Edges,
	Radius,
	Size,
	Paint,
	Color,
	Color_Opt,
	F32_Opt,
	Shadow,
}

Prop_Info :: struct {
	offset: uintptr,
	size:   int,
	kind:   Prop_Kind,
}

@(rodata)
PROP_TABLE := [Prop]Prop_Info {
	.W              = {offset_of(Props, w), size_of(Size), .Size},
	.H              = {offset_of(Props, h), size_of(Size), .Size},
	.Min_W          = {offset_of(Props, min_w), size_of(f32), .F32},
	.Min_H          = {offset_of(Props, min_h), size_of(f32), .F32},
	.Max_W          = {offset_of(Props, max_w), size_of(f32), .F32},
	.Max_H          = {offset_of(Props, max_h), size_of(f32), .F32},
	.Pad            = {offset_of(Props, pad), size_of(Edges), .Edges},
	.Margin         = {offset_of(Props, margin), size_of(Edges), .Edges},
	.Gap            = {offset_of(Props, gap), size_of(Vec2), .Vec2},
	.Inset          = {offset_of(Props, inset), size_of(Edges), .Edges},
	.Bg             = {offset_of(Props, bg), size_of(Paint), .Paint},
	.Border_Color   = {
		offset_of(Props, border) + offset_of(Border, color),
		size_of(Color),
		.Color,
	},
	.Border_Width   = {
		offset_of(Props, border) + offset_of(Border, width),
		size_of(Edges),
		.Edges,
	},
	.Radius         = {offset_of(Props, radius), size_of(Radius), .Radius},
	.Shadow         = {offset_of(Props, shadow), size_of(Shadow), .Shadow},
	.Opacity        = {offset_of(Props, opacity), size_of(Maybe(f32)), .F32_Opt},
	.Color          = {offset_of(Props, color), size_of(Maybe(Color)), .Color_Opt},
	.Font_Size      = {offset_of(Props, font_size), size_of(f32), .F32},
	.Line_Height    = {offset_of(Props, line_height), size_of(f32), .F32},
	.Letter_Spacing = {offset_of(Props, letter_spacing), size_of(f32), .F32},
}

Mode_Prop :: enum u8 {
	Dir,
	Wrap,
	Justify,
	Align,
	Align_Self,
	Order,
	Aspect,
	Position,
	Z,
	Overflow,
	Font,
	Text_Align,
	Text_Wrap,
	Cursor,
}

Mode_Set :: bit_set[Mode_Prop;u16]

Mode_Info :: struct {
	offset: uintptr,
	size:   int,
}

@(rodata)
MODE_TABLE := [Mode_Prop]Mode_Info {
	.Dir        = {offset_of(Props, dir), size_of(Direction)},
	.Wrap       = {offset_of(Props, wrap), size_of(Wrap)},
	.Justify    = {offset_of(Props, justify), size_of(Justify)},
	.Align      = {offset_of(Props, align), size_of(Align)},
	.Align_Self = {offset_of(Props, align_self), size_of(Align)},
	.Order      = {offset_of(Props, order), size_of(i16)},
	.Aspect     = {offset_of(Props, aspect), size_of(f32)},
	.Position   = {offset_of(Props, position), size_of(Position)},
	.Z          = {offset_of(Props, z), size_of(i16)},
	.Overflow   = {offset_of(Props, overflow), size_of([2]Overflow)},
	.Font       = {offset_of(Props, font), size_of(Font)},
	.Text_Align = {offset_of(Props, text_align), size_of(Text_Align)},
	.Text_Wrap  = {offset_of(Props, text_wrap), size_of(Text_Wrap)},
	.Cursor     = {offset_of(Props, cursor), size_of(Cursor)},
}

INHERITED_PROPS :: Prop_Set{.Color, .Font_Size, .Line_Height, .Letter_Spacing}

INHERITED_MODES :: Mode_Set{.Font, .Text_Align, .Text_Wrap, .Cursor}

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

CARRIED_STATES :: State_Set{.Group_Hover, .Focus_Within, .Disabled}

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
