package loom

import "core:fmt"
import "core:io"
import "core:strings"

Writer :: io.Writer

@(private)
DEBUG_FONT_SIZE :: f32(12)

@(private)
DEBUG_PAD :: f32(8)

@(private)
DEBUG_INSET :: f32(12)

@(private)
DEBUG_CHAIN_MAX :: 8

@(private)
DEBUG_RECT_MAX :: 4096

@(private)
DEBUG_ALL_RECTS :: Color{0, 200, 255, 40}

@(private)
DEBUG_MARGIN :: Color{246, 178, 107, 140}

@(private)
DEBUG_BORDER :: Color{255, 229, 153, 150}

@(private)
DEBUG_PADDING :: Color{147, 196, 125, 150}

@(private)
DEBUG_CONTENT :: Color{111, 168, 220, 150}

@(private)
DEBUG_PANEL_ALPHA :: f32(0.94)

Stats :: struct {
	live_nodes:    int,
	free_nodes:    int,
	state_blocks:  int,
	frame_index:   u64,
	open_depth:    int,
	commands:      int,
	text_entries:  int,
	text_hits:     int,
	text_misses:   int,
	text_measures: int,
}

stats :: proc() -> Stats {
	return stats_of(ctx_of())
}

@(private)
stats_of :: proc(ctx: ^Context) -> Stats {
	return Stats {
		live_nodes = ctx.live_nodes,
		free_nodes = ctx.free_count,
		state_blocks = ctx.state_blocks,
		frame_index = ctx.frame_index,
		open_depth = len(ctx.open),
		commands = ctx.cmd_count,
		text_entries = len(ctx.text_cache),
		text_hits = ctx.text_hits,
		text_misses = ctx.text_misses,
		text_measures = ctx.text_measures,
	}
}

debug_overlay :: proc(enabled: bool) {
	ctx_of().debug = enabled
}

debug_rects :: proc(enabled: bool) {
	ctx_of().debug_rects = enabled
}

dump_tree :: proc(w: Writer) {
	ctx := ctx_of()
	if ctx.root == nil {
		return
	}
	dump_node(w, ctx.root, 0)
}

dump_tree_string :: proc(allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	dump_tree(strings.to_writer(&b))
	return strings.to_string(b)
}

@(private)
dump_node :: proc(w: Writer, n: ^Node, depth: int) {
	for _ in 0 ..< depth {
		io.write_string(w, "  ")
	}

	if n.el.key != "" {
		fmt.wprintf(w, "#%s", n.el.key)
	} else {
		fmt.wprintf(w, "#%016x", u64(n.id))
	}

	for s in State {
		if s in n.state {
			fmt.wprintf(w, ".%s", state_name(s))
		}
	}

	fmt.wprintf(w, " [%v]", n.computed.dir)
	fmt.wprintf(w, " rect(%v,%v,%v,%v)", n.rect.x, n.rect.y, n.rect.w, n.rect.h)

	if n.el.text != "" {
		fmt.wprintf(w, " text=%q", n.el.text)
	}
	if c, ok := n.computed.bg.(Color); ok {
		fmt.wprintf(w, " bg=#%02X%02X%02X%02X", c[0], c[1], c[2], c[3])
	}
	if n.computed.pad != {} {
		p := n.computed.pad
		fmt.wprintf(w, " pad=(%v,%v,%v,%v)", p.l, p.t, p.r, p.b)
	}
	if n.flags != {} {
		io.write_string(w, " flags=[")
		first := true
		for f in Flag {
			if f not_in n.flags {
				continue
			}
			if !first {
				io.write_string(w, ",")
			}
			fmt.wprintf(w, "%v", f)
			first = false
		}
		io.write_string(w, "]")
	}
	io.write_string(w, "\n")

	for c := n.first_child; c != nil; c = c.next {
		dump_node(w, c, depth + 1)
	}
}

@(private)
state_name :: proc(s: State) -> string {
	switch s {
	case .Hover:
		return "hover"
	case .Active:
		return "active"
	case .Focus:
		return "focus"
	case .Focus_Within:
		return "focus-within"
	case .Disabled:
		return "disabled"
	case .Checked:
		return "checked"
	case .Open:
		return "open"
	case .Group_Hover:
		return "group-hover"
	}
	return "?"
}

dump_list :: proc(w: Writer, list: Draw_List) {
	depth := 0
	for cmd in list.cmds {
		if _, ok := cmd.(Cmd_Pop_Clip); ok {
			depth = max(depth - 1, 0)
		}
		for _ in 0 ..< depth {
			io.write_string(w, "  ")
		}
		dump_cmd(w, cmd)
		io.write_string(w, "\n")
		if _, ok := cmd.(Cmd_Push_Clip); ok {
			depth += 1
		}
	}
}

dump_list_string :: proc(list: Draw_List, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	dump_list(strings.to_writer(&b), list)
	return strings.to_string(b)
}

@(private)
dump_cmd :: proc(w: Writer, cmd: Draw_Command) {
	switch c in cmd {
	case Cmd_Rect:
		fmt.wprintf(w, "rect(%v,%v,%v,%v)", c.rect.x, c.rect.y, c.rect.w, c.rect.h)
		if paint_visible(c.paint) {
			io.write_string(w, " bg=")
			dump_paint(w, c.paint)
		}
		if c.radius != {} {
			fmt.wprintf(w, " r=(%v,%v,%v,%v)", c.radius.tl, c.radius.tr, c.radius.br, c.radius.bl)
		}
		if border_visible(c.border) {
			b := c.border.width
			fmt.wprintf(w, " border=(%v,%v,%v,%v)/", b.l, b.t, b.r, b.b)
			dump_color(w, c.border.color)
		}
		if shadow_visible(c.shadow) {
			s := c.shadow
			fmt.wprintf(w, " shadow=(%v,%v)/%v/%v/", s.offset.x, s.offset.y, s.blur, s.spread)
			dump_color(w, s.color)
			if s.inset {
				io.write_string(w, ",inset")
			}
		}
	case Cmd_Text:
		fmt.wprintf(w, "text(%v,%v) %q f=%v s=%v ", c.pos.x, c.pos.y, c.text, u32(c.font), c.size)
		if c.spacing != 0 {
			fmt.wprintf(w, "ls=%v ", c.spacing)
		}
		dump_color(w, c.color)
	case Cmd_Image:
		fmt.wprintf(w, "image(%v,%v,%v,%v)", c.rect.x, c.rect.y, c.rect.w, c.rect.h)
		fmt.wprintf(w, " tex=%v uv=(%v,%v,%v,%v) ", u32(c.tex), c.uv.x, c.uv.y, c.uv.w, c.uv.h)
		dump_color(w, c.tint)
		if c.radius != {} {
			fmt.wprintf(w, " r=(%v,%v,%v,%v)", c.radius.tl, c.radius.tr, c.radius.br, c.radius.bl)
		}
	case Cmd_Push_Clip:
		fmt.wprintf(w, "push_clip(%v,%v,%v,%v)", c.rect.x, c.rect.y, c.rect.w, c.rect.h)
		if c.radius != {} {
			fmt.wprintf(w, " r=(%v,%v,%v,%v)", c.radius.tl, c.radius.tr, c.radius.br, c.radius.bl)
		}
	case Cmd_Pop_Clip:
		io.write_string(w, "pop_clip")
	case Cmd_Custom:
		io.write_string(w, "custom ")
		dump_ref(w, c.node)
	}
}

@(private)
dump_ref :: proc(w: Writer, n: ^Node) {
	if n == nil {
		io.write_string(w, "#nil")
		return
	}
	if n.el.key != "" {
		fmt.wprintf(w, "#%s", n.el.key)
		return
	}
	fmt.wprintf(w, "#%016x", u64(n.id))
}

@(private)
dump_color :: proc(w: Writer, c: Color) {
	fmt.wprintf(w, "#%02X%02X%02X%02X", c[0], c[1], c[2], c[3])
}

@(private)
dump_paint :: proc(w: Writer, p: Paint) {
	switch v in p {
	case Color:
		dump_color(w, v)
	case Gradient:
		fmt.wprintf(w, "grad(%v,%v", v.kind, v.angle)
		for s in v.stops {
			io.write_string(w, ",")
			dump_color(w, s.color)
			fmt.wprintf(w, "@%v", s.t)
		}
		io.write_string(w, ")")
	}
}

@(private)
emit_debug :: proc(e: ^Emitter, order: []Paint_Entry) {
	ctx := e.ctx
	if !ctx.debug && !ctx.debug_rects {
		return
	}

	hits, misses, measures := ctx.text_hits, ctx.text_misses, ctx.text_measures
	st := stats_of(ctx)

	if ctx.debug_rects {
		debug_all_rects(e, order)
	}
	if ctx.debug {
		n := node_alive(ctx, ctx.hovered_id)
		if n != nil {
			debug_box_model(e, n)
		}
		debug_panel(e, n, st)
	}

	ctx.text_hits, ctx.text_misses, ctx.text_measures = hits, misses, measures
}

@(private)
debug_outline :: proc(e: ^Emitter, r: Rect, c: Color) {
	if rect_is_empty(r) {
		return
	}
	emit_cmd(e, Cmd_Rect{rect = r, border = Border{width = all(1), color = c}})
}

@(private)
debug_all_rects :: proc(e: ^Emitter, order: []Paint_Entry) {
	vp := Rect{0, 0, e.ctx.input.viewport.x, e.ctx.input.viewport.y}
	drawn := 0
	for entry in order {
		if drawn >= DEBUG_RECT_MAX {
			return
		}
		if rect_is_empty(rect_intersect(entry.node.rect, vp)) {
			continue
		}
		debug_outline(e, entry.node.rect, DEBUG_ALL_RECTS)
		drawn += 1
	}
}

@(private)
debug_box_model :: proc(e: ^Emitter, n: ^Node) {
	m := n.computed.margin
	debug_outline(
		e,
		{
			n.rect.x - m.l,
			n.rect.y - m.t,
			max(n.rect.w + m.l + m.r, 0),
			max(n.rect.h + m.t + m.b, 0),
		},
		DEBUG_MARGIN,
	)
	debug_outline(e, n.rect, DEBUG_BORDER)
	debug_outline(e, clip_box(n), DEBUG_PADDING)
	debug_outline(e, content_rect(n), DEBUG_CONTENT)
}

@(private)
debug_style :: proc(ctx: ^Context) -> Text_Style {
	p := ctx.cfg.root
	if p.font_size <= 0 {
		p.font_size = DEBUG_FONT_SIZE
	}
	st := text_style(ctx, &p)
	if st.line_h <= 0 {
		st.line_h = p.font_size * 1.25
	}
	if st.ascent <= 0 {
		st.ascent = p.font_size * 0.8
	}
	return st
}

@(private)
debug_width :: proc(ctx: ^Context, st: Text_Style, s: string) -> f32 {
	w := measure_run(ctx, st, s)
	if w <= 0 {
		w = f32(len(s)) * st.size * 0.5
	}
	return w
}

@(private)
debug_panel :: proc(e: ^Emitter, n: ^Node, st: Stats) {
	ctx := e.ctx
	lines := debug_lines(ctx, n, st)
	if len(lines) == 0 {
		return
	}

	ts := debug_style(ctx)
	w: f32
	for l in lines {
		w = max(w, debug_width(ctx, ts, l))
	}
	w += DEBUG_PAD * 2
	h := ts.line_h * f32(len(lines)) + DEBUG_PAD * 2

	vp := ctx.input.viewport
	box := Rect{max(vp.x - w - DEBUG_INSET, DEBUG_INSET), DEBUG_INSET, w, h}
	if n != nil && !rect_is_empty(rect_intersect(box, n.rect)) {
		box.x = DEBUG_INSET
	}

	th := &ctx.theme
	emit_cmd(
		e,
		Cmd_Rect {
			rect = box,
			paint = fade(th.overlay, DEBUG_PANEL_ALPHA),
			radius = rad(6),
			border = Border{width = all(1), color = th.border},
		},
	)
	for l, i in lines {
		emit_cmd(
			e,
			Cmd_Text {
				pos = {box.x + DEBUG_PAD, box.y + DEBUG_PAD + f32(i) * ts.line_h + ts.ascent},
				text = l,
				font = ts.font,
				size = ts.size,
				spacing = ts.spacing,
				color = th.text,
			},
		)
	}
}

@(private)
debug_lines :: proc(ctx: ^Context, n: ^Node, st: Stats) -> []string {
	lines := make([dynamic]string, 0, 16, ctx.frame_allocator)

	if n == nil {
		append(&lines, "no hovered node")
	} else {
		if n.el.key != "" {
			append(&lines, fmt.aprintf("#%s", n.el.key, allocator = ctx.frame_allocator))
		} else {
			append(&lines, fmt.aprintf("#%016x", u64(n.id), allocator = ctx.frame_allocator))
		}
		if loc, ok := ctx.seen[n.id]; ok {
			append(
				&lines,
				fmt.aprintf(
					"%s(%v:%v)",
					loc.file_path,
					loc.line,
					loc.column,
					allocator = ctx.frame_allocator,
				),
			)
		}
		append(
			&lines,
			fmt.aprintf(
				"state: %s",
				debug_states(ctx, n.state),
				allocator = ctx.frame_allocator,
			),
		)
		append(
			&lines,
			fmt.aprintf(
				"rect: %v,%v %vx%v",
				n.rect.x,
				n.rect.y,
				n.rect.w,
				n.rect.h,
				allocator = ctx.frame_allocator,
			),
		)
		append(
			&lines,
			fmt.aprintf(
				"size: w=%s h=%s",
				debug_size(ctx, n.computed.w),
				debug_size(ctx, n.computed.h),
				allocator = ctx.frame_allocator,
			),
		)
		append(
			&lines,
			fmt.aprintf(
				"scroll: %v,%v content: %v,%v",
				n.scroll.x,
				n.scroll.y,
				n.content.x,
				n.content.y,
				allocator = ctx.frame_allocator,
			),
		)
		append(
			&lines,
			fmt.aprintf(
				"chain: %s",
				debug_chain(ctx, n),
				allocator = ctx.frame_allocator,
			),
		)
		append(&lines, "")
	}

	append(
		&lines,
		fmt.aprintf(
			"nodes %v  free %v  cmds %v",
			st.live_nodes,
			st.free_nodes,
			st.commands,
			allocator = ctx.frame_allocator,
		),
	)
	append(
		&lines,
		fmt.aprintf(
			"text %v  hit %v  miss %v  measure %v",
			st.text_entries,
			st.text_hits,
			st.text_misses,
			st.text_measures,
			allocator = ctx.frame_allocator,
		),
	)
	append(
		&lines,
		fmt.aprintf(
			"frame %v  animating %v",
			st.frame_index,
			ctx.animating || ctx.scrolling,
			allocator = ctx.frame_allocator,
		),
	)
	return lines[:]
}

@(private)
debug_states :: proc(ctx: ^Context, set: State_Set) -> string {
	if set == {} {
		return "-"
	}
	b := strings.builder_make(ctx.frame_allocator)
	first := true
	for s in State {
		if s not_in set {
			continue
		}
		if !first {
			strings.write_string(&b, " ")
		}
		strings.write_string(&b, state_name(s))
		first = false
	}
	return strings.to_string(b)
}

@(private)
debug_chain :: proc(ctx: ^Context, n: ^Node) -> string {
	chain: [DEBUG_CHAIN_MAX]^Node
	count := 0
	for p := n.parent; p != nil && count < DEBUG_CHAIN_MAX; p = p.parent {
		chain[count] = p
		count += 1
	}
	if count == 0 {
		return "-"
	}

	b := strings.builder_make(ctx.frame_allocator)
	for i := count - 1; i >= 0; i -= 1 {
		p := chain[i]
		if p.el.key != "" {
			strings.write_string(&b, p.el.key)
		} else {
			fmt.sbprintf(&b, "%016x", u64(p.id))
		}
		if i > 0 {
			strings.write_string(&b, " > ")
		}
	}
	return strings.to_string(b)
}

@(private)
debug_size :: proc(ctx: ^Context, s: Size) -> string {
	switch v in s {
	case Px:
		return fmt.aprintf("%v", f32(v), allocator = ctx.frame_allocator)
	case Pct:
		return fmt.aprintf("%v%%", f32(v), allocator = ctx.frame_allocator)
	case Grow:
		return fmt.aprintf("grow(%v)", f32(v), allocator = ctx.frame_allocator)
	case Fit:
		return v == .Content ? "fit" : "stretch"
	}
	return "auto"
}
