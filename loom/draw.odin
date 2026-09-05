package loom

MAX_CLIP_DEPTH :: 32

@(private)
DEFAULT_TEXT_COLOR :: LOOM_DARK.text

@(private)
WHITE :: Color{255, 255, 255, 255}

Cmd_Rect :: struct {
	rect:   Rect,
	paint:  Paint,
	radius: Radius,
	border: Border,
	shadow: Shadow,
}

Cmd_Text :: struct {
	pos:     Vec2,
	text:    string,
	font:    Font,
	size:    f32,
	spacing: f32,
	color:   Color,
}

Cmd_Image :: struct {
	rect:   Rect,
	tex:    Texture,
	uv:     Rect,
	tint:   Color,
	radius: Radius,
}

Cmd_Line :: struct {
	a, b:  Vec2,
	width: f32,
	color: Color,
}

Cmd_Poly :: struct {
	points: []Vec2,
	color:  Color,
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
	Cmd_Line,
	Cmd_Poly,
	Cmd_Push_Clip,
	Cmd_Pop_Clip,
	Cmd_Custom,
}

Draw_List :: struct {
	cmds: []Draw_Command,
}

@(private)
Paint_Entry :: struct {
	node:  ^Node,
	clip:  Rect,
	alpha: f32,
	depth: int,
	clips: bool,
}

@(private)
Float_Seed :: struct {
	node:  ^Node,
	alpha: f32,
}

@(private)
Emitter :: struct {
	ctx:      ^Context,
	cmds:     [dynamic]Draw_Command,
	clip_at:  [MAX_CLIP_DEPTH]int,
	clip_top: int,
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
clip_radius :: proc(n: ^Node) -> Radius {
	r := n.computed.radius
	b := n.computed.border.width
	return {
		max(r.tl - max(b.l, b.t), 0),
		max(r.tr - max(b.t, b.r), 0),
		max(r.br - max(b.r, b.b), 0),
		max(r.bl - max(b.b, b.l), 0),
	}
}

@(private)
content_rect :: proc(n: ^Node) -> Rect {
	e := inner_edges(&n.computed)
	return {
		n.rect.x + e.l,
		n.rect.y + e.t,
		max(n.rect.w - e.l - e.r, 0),
		max(n.rect.h - e.t - e.b, 0),
	}
}

@(private)
rect_is_empty :: proc(r: Rect) -> bool {
	return r.w <= 0 || r.h <= 0
}

@(private)
rect_union :: proc(a, b: Rect) -> Rect {
	x0 := min(a.x, b.x)
	y0 := min(a.y, b.y)
	x1 := max(a.x + a.w, b.x + b.w)
	y1 := max(a.y + a.h, b.y + b.h)
	return {x0, y0, x1 - x0, y1 - y0}
}

@(private)
node_alpha :: proc(n: ^Node) -> f32 {
	if v, ok := n.computed.opacity.?; ok {
		return clamp(v, 0, 1)
	}
	return 1
}

@(private)
paint_visible :: proc(p: Paint) -> bool {
	switch v in p {
	case Color:
		return v[3] != 0
	case Gradient:
		return len(v.stops) > 0
	}
	return false
}

@(private)
border_visible :: proc(b: Border) -> bool {
	return b.width != Edges{} && b.color[3] != 0
}

@(private)
shadow_visible :: proc(s: Shadow) -> bool {
	return s.color[3] != 0
}

@(private)
shadow_bounds :: proc(r: Rect, s: Shadow) -> Rect {
	if s.inset || s.color[3] == 0 {
		return r
	}
	g := s.blur + s.spread
	return rect_union(r, {r.x + s.offset.x - g, r.y + s.offset.y - g, r.w + g * 2, r.h + g * 2})
}

@(private)
fold_color :: proc(c: Color, a: f32) -> Color {
	return a >= 1 ? c : fade(c, a)
}

@(private)
fold_paint :: proc(ctx: ^Context, p: Paint, a: f32) -> Paint {
	switch v in p {
	case Color:
		return fold_color(v, a)
	case Gradient:
		g := v
		if len(v.stops) > 0 {
			stops := make([]Stop, len(v.stops), ctx.frame_allocator)
			for s, i in v.stops {
				stops[i] = Stop {
					t     = s.t,
					color = fold_color(s.color, a),
				}
			}
			g.stops = stops
		}
		return g
	}
	return p
}

@(private)
paint_order :: proc(ctx: ^Context, root: ^Node) -> []Paint_Entry {
	if root == nil {
		return nil
	}
	vp := Rect{0, 0, ctx.input.viewport.x, ctx.input.viewport.y}
	return paint_order_space(ctx, root, nil, vp)
}

@(private)
paint_order_viewport :: proc(ctx: ^Context, v: ^Viewport) -> []Paint_Entry {
	if v == nil || v.node == nil {
		return nil
	}
	return paint_order_space(ctx, v.node, v, {0, 0, v.rect.w, v.rect.h})
}

@(private)
paint_order_space :: proc(
	ctx: ^Context,
	seed: ^Node,
	space: ^Viewport,
	clip: Rect,
) -> []Paint_Entry {
	out := make([dynamic]Paint_Entry, 0, max(ctx.live_nodes, 8), ctx.frame_allocator)
	floats := make([dynamic]Float_Seed, 0, 8, ctx.frame_allocator)

	paint_walk(ctx, seed, clip, space, 1, 0, &out, &floats)
	for i := 0; i < len(floats); i += 1 {
		paint_walk(ctx, floats[i].node, clip, space, floats[i].alpha, 0, &out, &floats)
	}
	return out[:]
}

@(private)
paint_walk :: proc(
	ctx: ^Context,
	n: ^Node,
	clip: Rect,
	space: ^Viewport,
	alpha: f32,
	depth: int,
	out: ^[dynamic]Paint_Entry,
	floats: ^[dynamic]Float_Seed,
) {
	a := alpha * node_alpha(n)
	clips := node_clips(n)
	append(out, Paint_Entry{node = n, clip = clip, alpha = a, depth = depth, clips = clips})

	child_clip := clip
	if clips {
		child_clip = rect_intersect(clip, clip_box(n))
		if rect_is_empty(child_clip) {
			return
		}
	}

	count := 0
	for c := n.first_child; c != nil; c = c.next {
		count += 1
	}
	if count == 0 {
		return
	}

	items := paint_children(ctx, n, count)
	if items == nil {
		for c := n.first_child; c != nil; c = c.next {
			paint_child(ctx, c, child_clip, space, a, depth, out, floats)
		}
		return
	}
	for c in items {
		paint_child(ctx, c, child_clip, space, a, depth, out, floats)
	}
}

@(private)
paint_child :: proc(
	ctx: ^Context,
	c: ^Node,
	clip: Rect,
	space: ^Viewport,
	alpha: f32,
	depth: int,
	out: ^[dynamic]Paint_Entry,
	floats: ^[dynamic]Float_Seed,
) {
	if c.viewport != space {
		return
	}
	if .Floating in c.flags {
		append(floats, Float_Seed{node = c, alpha = alpha})
		return
	}
	paint_walk(ctx, c, clip, space, alpha, depth + 1, out, floats)
}

@(private)
paint_children :: proc(ctx: ^Context, n: ^Node, count: int) -> []^Node {
	z := n.first_child.computed.z
	mixed := false
	for c := n.first_child; c != nil; c = c.next {
		if c.computed.z != z {
			mixed = true
			break
		}
	}
	if !mixed {
		return nil
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
	return items
}

@(private)
emit :: proc(ctx: ^Context) {
	ctx.draw_list = {}
	ctx.cmd_count = 0
	if ctx.root == nil {
		return
	}

	list, count := emit_order(ctx, paint_order(ctx, ctx.root), true)
	ctx.cmd_count = count
	ctx.draw_list = list
}

@(private)
emit_order :: proc(ctx: ^Context, order: []Paint_Entry, debug: bool) -> (Draw_List, int) {
	e := Emitter {
		ctx  = ctx,
		cmds = make([dynamic]Draw_Command, 0, max(ctx.live_nodes * 2, 64), ctx.frame_allocator),
	}

	for entry in order {
		unwind_clips(&e, entry.depth)
		emit_entry(&e, entry)
	}
	unwind_clips(&e, 0)

	count := len(e.cmds)
	if debug {
		emit_debug(&e, order)
	}
	return Draw_List{cmds = e.cmds[:]}, count
}

@(private)
emit_cmd :: proc(e: ^Emitter, cmd: Draw_Command) {
	append(&e.cmds, cmd)
}

@(private)
open_clip :: proc(e: ^Emitter, depth: int, rect: Rect, radius: Radius) {
	assert(e.clip_top < MAX_CLIP_DEPTH, "loom: clip nesting deeper than MAX_CLIP_DEPTH")
	e.clip_at[e.clip_top] = depth
	e.clip_top += 1
	emit_cmd(e, Cmd_Push_Clip{rect = rect, radius = radius})
}

@(private)
unwind_clips :: proc(e: ^Emitter, depth: int) {
	for e.clip_top > 0 && e.clip_at[e.clip_top - 1] >= depth {
		e.clip_top -= 1
		emit_cmd(e, Cmd_Pop_Clip{})
	}
}

@(private)
emit_entry :: proc(e: ^Emitter, entry: Paint_Entry) {
	n := entry.node
	if entry.alpha <= 0 {
		return
	}

	p := &n.computed
	if rect_is_empty(rect_intersect(shadow_bounds(n.rect, p.shadow), entry.clip)) {
		return
	}

	emit_rect(e, n, entry.alpha)

	if entry.clips {
		open_clip(e, entry.depth, clip_box(n), clip_radius(n))
	}

	emit_image(e, n, entry.alpha)
	emit_paint(e, n, false, entry.alpha)
	emit_runs(e, n, entry.clip, entry.alpha)
	emit_custom(e, n)
	emit_paint(e, n, true, entry.alpha)
}

@(private)
emit_rect :: proc(e: ^Emitter, n: ^Node, alpha: f32) {
	p := &n.computed
	if !paint_visible(p.bg) && !border_visible(p.border) && !shadow_visible(p.shadow) {
		return
	}
	if rect_is_empty(n.rect) {
		return
	}

	cmd := Cmd_Rect {
		rect   = n.rect,
		paint  = fold_paint(e.ctx, p.bg, alpha),
		radius = p.radius,
	}
	if border_visible(p.border) {
		cmd.border = Border {
			width = p.border.width,
			color = fold_color(p.border.color, alpha),
		}
	}
	if shadow_visible(p.shadow) {
		cmd.shadow = p.shadow
		cmd.shadow.color = fold_color(p.shadow.color, alpha)
	}
	if !paint_visible(cmd.paint) && !border_visible(cmd.border) && !shadow_visible(cmd.shadow) {
		return
	}
	emit_cmd(e, cmd)
}

@(private)
emit_image :: proc(e: ^Emitter, n: ^Node, alpha: f32) {
	if n.el.texture == 0 {
		return
	}
	r := content_rect(n)
	if rect_is_empty(r) {
		return
	}

	tint := n.el.tint
	if tint == (Color{}) {
		tint = WHITE
	}
	tint = fold_color(tint, alpha)
	if tint[3] == 0 {
		return
	}

	emit_cmd(
		e,
		Cmd_Image {
			rect = r,
			tex = n.el.texture,
			uv = n.el.uv,
			tint = tint,
			radius = n.computed.radius,
		},
	)
}

@(private)
emit_runs :: proc(e: ^Emitter, n: ^Node, clip: Rect, alpha: f32) {
	runs := text_runs(n)
	if len(runs) == 0 {
		return
	}

	p := &n.computed
	col := e.ctx.theme.text
	if c, ok := p.color.?; ok {
		col = c
	}
	col = fold_color(col, alpha)

	st := text_style(e.ctx, p)
	lh := st.line_h > 0 ? st.line_h : st.size
	top := clip.y - lh
	bot := clip.y + clip.h + lh

	for r in runs {
		if r.text == "" {
			continue
		}
		if r.pos.y < top || r.pos.y > bot {
			continue
		}
		rc := col
		if c, ok := r.color.?; ok {
			rc = fold_color(c, alpha)
		}
		if rc[3] == 0 {
			continue
		}
		emit_cmd(
			e,
			Cmd_Text {
				pos = r.pos,
				text = r.text,
				font = st.font,
				size = st.size,
				spacing = st.spacing,
				color = rc,
			},
		)
	}
}

@(private)
emit_custom :: proc(e: ^Emitter, n: ^Node) {
	if n.draw == nil {
		return
	}
	emit_cmd(e, Cmd_Custom{node = n, draw = n.draw, user = n.draw_user})
}
