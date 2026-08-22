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

@(private)
Paint_Entry :: struct {
	node: ^Node,
	clip: Rect,
}

@(private)
node_clips :: proc(n: ^Node) -> bool {
	if n.flags & {.Clip, .Scroll_X, .Scroll_Y} != {} {
		return true
	}
	return n.computed.overflow[0] != .Visible || n.computed.overflow[1] != .Visible
}

@(private)
clip_box :: proc(n: ^Node) -> Rect {
	b := n.computed.border.width
	return {
		n.rect.x + b.l,
		n.rect.y + b.t,
		max(n.rect.w - b.l - b.r, 0),
		max(n.rect.h - b.t - b.b, 0),
	}
}

@(private)
paint_order :: proc(ctx: ^Context, root: ^Node) -> []Paint_Entry {
	if root == nil {
		return nil
	}
	out := make([dynamic]Paint_Entry, 0, max(ctx.live_nodes, 8), ctx.frame_allocator)
	floats := make([dynamic]^Node, 0, 8, ctx.frame_allocator)

	vp := Rect{0, 0, ctx.input.viewport.x, ctx.input.viewport.y}
	paint_walk(ctx, root, vp, &out, &floats)
	for i := 0; i < len(floats); i += 1 {
		paint_walk(ctx, floats[i], vp, &out, &floats)
	}
	return out[:]
}

@(private)
paint_walk :: proc(
	ctx: ^Context,
	n: ^Node,
	clip: Rect,
	out: ^[dynamic]Paint_Entry,
	floats: ^[dynamic]^Node,
) {
	append(out, Paint_Entry{node = n, clip = clip})

	child_clip := clip
	if node_clips(n) {
		child_clip = rect_intersect(clip, clip_box(n))
	}

	count := 0
	for c := n.first_child; c != nil; c = c.next {
		count += 1
	}
	if count == 0 {
		return
	}

	items := make([]^Node, count, ctx.frame_allocator)
	at := 0
	for c := n.first_child; c != nil; c = c.next {
		items[at] = c
		at += 1
	}

	for i in 1 ..< count {
		c := items[i]
		j := i - 1
		for j >= 0 && items[j].computed.z > c.computed.z {
			items[j + 1] = items[j]
			j -= 1
		}
		items[j + 1] = c
	}

	for c in items {
		if .Floating in c.flags {
			append(floats, c)
			continue
		}
		paint_walk(ctx, c, child_clip, out, floats)
	}
}
