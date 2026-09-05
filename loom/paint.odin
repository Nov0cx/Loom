package loom

// A shape painted into the node's own slot of the draw list, in coordinates
// local to its border box. It is how a widget draws what props cannot describe:
// a caret, a selection band, an underline, a chevron.
@(private)
Paint_Kind :: enum u8 {
	Line,
	Poly,
	Rect,
}

@(private)
Paint_Op :: struct {
	kind:   Paint_Kind,
	over:   bool,
	a, b:   Vec2,
	width:  f32,
	color:  Color,
	radius: Radius,
	points: []Vec2,
}

@(private)
push_paint :: proc(op: Paint_Op) {
	n := current()
	if n == nil || op.color[3] == 0 {
		return
	}
	ctx := ctx_of()
	if n.paint == nil {
		n.paint = make([dynamic]Paint_Op, 0, 4, ctx.frame_allocator)
	}
	append(&n.paint, op)
}

// A line from `a` to `b`, in coordinates local to the current node.
paint_line :: proc(a, b: Vec2, width: f32, color: Color, over := true) {
	if width <= 0 {
		return
	}
	push_paint({kind = .Line, over = over, a = a, b = b, width = width, color = color})
}

// A filled polygon, wound either way. The points are copied, so a temporary
// slice is safe.
paint_poly :: proc(points: []Vec2, color: Color, over := true) {
	if len(points) < 3 {
		return
	}
	ctx := ctx_of()
	pts := make([]Vec2, len(points), ctx.frame_allocator)
	copy(pts, points)
	push_paint({kind = .Poly, over = over, color = color, points = pts})
}

// A filled rectangle. It goes under the text by default, where a caret and a
// selection band belong.
paint_rect :: proc(rect: Rect, color: Color, radius: Radius = {}, over := false) {
	if rect.w <= 0 || rect.h <= 0 {
		return
	}
	push_paint(
		{
			kind = .Rect,
			over = over,
			a = {rect.x, rect.y},
			b = {rect.w, rect.h},
			color = color,
			radius = radius,
		},
	)
}

@(private)
emit_paint :: proc(e: ^Emitter, n: ^Node, over: bool, alpha: f32) {
	if len(n.paint) == 0 {
		return
	}
	off := Vec2{n.rect.x, n.rect.y}

	for op in n.paint {
		if op.over != over {
			continue
		}
		col := fold_color(op.color, alpha)
		if col[3] == 0 {
			continue
		}

		switch op.kind {
		case .Line:
			emit_cmd(e, Cmd_Line{a = op.a + off, b = op.b + off, width = op.width, color = col})
		case .Poly:
			pts := make([]Vec2, len(op.points), e.ctx.frame_allocator)
			for p, i in op.points {
				pts[i] = p + off
			}
			emit_cmd(e, Cmd_Poly{points = pts, color = col})
		case .Rect:
			emit_cmd(
				e,
				Cmd_Rect {
					rect = {op.a.x + off.x, op.a.y + off.y, op.b.x, op.b.y},
					paint = col,
					radius = op.radius,
				},
			)
		}
	}
}
