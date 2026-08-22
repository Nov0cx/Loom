package loom

LAYOUT_EPS :: f32(0.01)
DISTRIBUTE_ROUNDS :: 16

@(private)
Layout :: struct {
	fit:         Vec2,
	size:        Vec2,
	pos:         Vec2,
	laid_size:   Vec2,
	baseline:    f32,
	frozen:      bool,
	relaid:      bool,
	laid:        bool,
	cross_known: bool,
}

@(private)
Line :: struct {
	first:    int,
	count:    int,
	main:     f32,
	cross:    f32,
	pos:      f32,
	baseline: f32,
}

@(private)
layout :: proc(ctx: ^Context) {
	r := ctx.root
	if r == nil {
		return
	}

	fit_node(ctx, r)

	vp := ctx.input.viewport
	p := &r.computed
	for a in Axis {
		i := int(a)
		s := axis_size(p, a)
		v, ok := definite_size(s, vp[i], true)
		if !ok {
			v = size_is_fit(s) ? r.lay.fit[i] : vp[i]
		}
		r.lay.size[i] = axis_clamp(v, p, a)
	}

	layout_node(ctx, r, axis_pair(.X, true, true))
	place(ctx, r, {0, 0})
}

@(private)
fit_node :: proc(ctx: ^Context, n: ^Node) {
	n.lay = new(Layout, ctx.frame_allocator)

	for c := n.first_child; c != nil; c = c.next {
		fit_node(ctx, c)
	}

	p := &n.computed
	ax := axis_of(p.dir)
	cx := cross_axis(ax)
	mi, ci := int(ax), int(cx)

	content: Vec2
	if n.el.text != "" {
		content = measure_text_node(ctx, n, 0)
	}

	main_sum, cross_max: f32
	count := 0
	for c := n.first_child; c != nil; c = c.next {
		cp := &c.computed
		if cp.position != .Flow {
			continue
		}
		main_sum += c.lay.fit[mi] + edge_total(cp.margin, ax)
		cross_max = max(cross_max, c.lay.fit[ci] + edge_total(cp.margin, cx))
		count += 1
	}
	if count > 1 {
		main_sum += gap_axis(p.gap, ax) * f32(count - 1)
	}
	content[mi] = max(content[mi], main_sum)
	content[ci] = max(content[ci], cross_max)

	inner := inner_edges(p)
	for a in Axis {
		i := int(a)
		v := content[i] + edge_total(inner, a)
		if d, ok := definite_size(axis_size(p, a), 0, false); ok {
			v = d
		}
		n.lay.fit[i] = axis_clamp(v, p, a)
	}
}

@(private)
layout_node :: proc(ctx: ^Context, n: ^Node, known: [Axis]bool) {
	p := &n.computed
	inner := inner_edges(p)

	cb: Vec2
	for a in Axis {
		i := int(a)
		base := known[a] ? n.lay.size[i] : n.lay.fit[i]
		cb[i] = max(base - edge_total(inner, a), 0)
	}

	text: Vec2
	if n.el.text != "" {
		text = measure_text_node(ctx, n, known[.X] ? cb.x : 0)
	}

	used := arrange(ctx, n, cb, known)

	for a in Axis {
		i := int(a)
		if known[a] {
			continue
		}
		v := max(used[i], text[i]) + edge_total(inner, a)
		n.lay.size[i] = axis_clamp(v, p, a)
	}

	n.lay.baseline = node_baseline(ctx, n, inner)
}

@(private)
node_baseline :: proc(ctx: ^Context, n: ^Node, inner: Edges) -> f32 {
	if n.el.text != "" {
		return inner.t + text_ascent(ctx, &n.computed)
	}
	for c := n.first_child; c != nil; c = c.next {
		if c.computed.position != .Flow {
			continue
		}
		return inner.t + c.lay.pos.y + c.lay.baseline
	}
	return n.lay.size.y + n.computed.margin.b
}

@(private)
arrange :: proc(ctx: ^Context, n: ^Node, cb: Vec2, known: [Axis]bool) -> Vec2 {
	p := &n.computed
	ax := axis_of(p.dir)
	cx := cross_axis(ax)
	mi, ci := int(ax), int(cx)

	items := gather_flow(ctx, n)
	if len(items) == 0 {
		return {}
	}

	gap_m := gap_axis(p.gap, ax)
	gap_c := gap_axis(p.gap, cx)
	single := p.wrap == .None && known[cx]
	shrink := !axis_overflows(p, n.flags, ax)

	for c in items {
		measure_item(ctx, c, p, ax, cx, cb, known, single)
	}

	lines := break_lines(ctx, items, cb[mi], known[ax], ax, p.wrap, gap_m)

	for &ln in lines {
		row := items[ln.first:][:ln.count]
		distribute(row, ax, known[ax] ? cb[mi] : ln.main, gap_m, shrink)

		for c in row {
			finish_item(ctx, c, ax, cx)
		}

		ln.main = line_main(row, ax, gap_m)
		ln.cross = single ? cb[ci] : line_cross(row, cx)

		if !single {
			for c in row {
				stretch_item(ctx, c, p, ax, cx, ln.cross)
			}
			ln.cross = line_cross(row, cx)
		}

		ln.baseline = 0
		for c in row {
			cp := &c.computed
			if cx != .Y || item_align(cp, p) != .Baseline {
				continue
			}
			ln.baseline = max(ln.baseline, cp.margin.t + c.lay.baseline)
		}
	}

	total_cross: f32
	for ln, i in lines {
		if i > 0 {
			total_cross += gap_c
		}
		total_cross += ln.cross
	}

	cross_extent := known[cx] ? cb[ci] : total_cross
	if p.wrap == .Wrap_Reverse {
		off := cross_extent
		for &ln in lines {
			off -= ln.cross
			ln.pos = off
			off -= gap_c
		}
	} else {
		off: f32
		for &ln in lines {
			ln.pos = off
			off += ln.cross + gap_c
		}
	}

	main_used: f32
	for ln in lines {
		main_used = max(main_used, ln.main)
		row := items[ln.first:][:ln.count]
		place_line(row, ln, p, ax, cx, known[ax] ? cb[mi] : ln.main, gap_m)
	}

	out: Vec2
	out[mi] = main_used
	out[ci] = total_cross
	return out
}

@(private)
measure_item :: proc(
	ctx: ^Context,
	c: ^Node,
	p: ^Props,
	ax, cx: Axis,
	cb: Vec2,
	known: [Axis]bool,
	single: bool,
) {
	cp := &c.computed
	lay := c.lay
	mi, ci := int(ax), int(cx)

	lay.frozen = false
	lay.relaid = false
	lay.laid = false
	lay.cross_known = false

	if v, ok := definite_size(axis_size(cp, cx), cb[ci], known[cx]); ok {
		lay.size[ci] = axis_clamp(v, cp, cx)
		lay.cross_known = true
	} else if single && will_stretch(cp, p, cx) {
		lay.size[ci] = axis_clamp(max(cb[ci] - edge_total(cp.margin, cx), 0), cp, cx)
		lay.cross_known = true
	}

	s := axis_size(cp, ax)
	if v, ok := definite_size(s, cb[mi], known[ax]); ok {
		lay.size[mi] = axis_clamp(v, cp, ax)
	} else if size_is_stretch(s) && known[ax] {
		lay.size[mi] = axis_clamp(max(cb[mi] - edge_total(cp.margin, ax), 0), cp, ax)
	} else if cp.aspect > 0 && lay.cross_known {
		lay.size[mi] = axis_clamp(derive_aspect(lay.size[ci], cp.aspect, ax), cp, ax)
	} else {
		layout_node(ctx, c, axis_pair(ax, false, lay.cross_known))
		lay.laid = true
		lay.laid_size = lay.size
	}
}

@(private)
finish_item :: proc(ctx: ^Context, c: ^Node, ax, cx: Axis) {
	cp := &c.computed
	lay := c.lay
	mi, ci := int(ax), int(cx)

	if !lay.cross_known && cp.aspect > 0 {
		lay.size[ci] = axis_clamp(derive_aspect(lay.size[mi], cp.aspect, cx), cp, cx)
		lay.cross_known = true
	}
	if lay.laid && lay.laid_size == lay.size {
		return
	}

	layout_node(ctx, c, axis_pair(ax, true, lay.cross_known))
	lay.laid = true
	lay.laid_size = lay.size
}

@(private)
stretch_item :: proc(ctx: ^Context, c: ^Node, p: ^Props, ax, cx: Axis, extent: f32) {
	cp := &c.computed
	lay := c.lay
	ci := int(cx)

	if lay.cross_known || lay.relaid || !will_stretch(cp, p, cx) {
		return
	}

	target := axis_clamp(max(extent - edge_total(cp.margin, cx), 0), cp, cx)
	if abs(target - lay.size[ci]) < LAYOUT_EPS {
		return
	}

	lay.size[ci] = target
	lay.cross_known = true
	lay.relaid = true
	layout_node(ctx, c, axis_pair(ax, true, true))
	lay.laid_size = lay.size
}

@(private)
place_line :: proc(row: []^Node, ln: Line, p: ^Props, ax, cx: Axis, extent, gap: f32) {
	mi, ci := int(ax), int(cx)
	free := max(extent - ln.main, 0)

	lead, between: f32
	switch p.justify {
	case .Start:
	case .Center:
		lead = free * 0.5
	case .End:
		lead = free
	case .Space_Between:
		between = ln.count > 1 ? free / f32(ln.count - 1) : 0
	case .Space_Around:
		between = ln.count > 0 ? free / f32(ln.count) : 0
		lead = between * 0.5
	case .Space_Evenly:
		between = free / f32(ln.count + 1)
		lead = between
	}

	cursor := lead
	for c in row {
		cp := &c.computed
		outer := c.lay.size[mi] + edge_total(cp.margin, ax)

		pos := cursor
		if is_reverse(p.dir) {
			pos = extent - cursor - outer
		}
		c.lay.pos[mi] = pos + edge_lead(cp.margin, ax)
		cursor += outer + gap + between

		al := item_align(cp, p)
		if al == .Baseline && cx != .Y {
			al = .Start
		}
		outer_c := c.lay.size[ci] + edge_total(cp.margin, cx)

		cross: f32
		switch al {
		case .Auto, .Stretch, .Start:
		case .Center:
			cross = max(ln.cross - outer_c, 0) * 0.5
		case .End:
			cross = max(ln.cross - outer_c, 0)
		case .Baseline:
			cross = max(ln.baseline - (cp.margin.t + c.lay.baseline), 0)
		}
		c.lay.pos[ci] = ln.pos + cross + edge_lead(cp.margin, cx)
	}
}

@(private)
line_main :: proc(row: []^Node, ax: Axis, gap: f32) -> (out: f32) {
	mi := int(ax)
	for c, i in row {
		if i > 0 {
			out += gap
		}
		out += c.lay.size[mi] + edge_total(c.computed.margin, ax)
	}
	return
}

@(private)
line_cross :: proc(row: []^Node, cx: Axis) -> (out: f32) {
	ci := int(cx)
	for c in row {
		out = max(out, c.lay.size[ci] + edge_total(c.computed.margin, cx))
	}
	return
}

@(private)
gather_flow :: proc(ctx: ^Context, n: ^Node) -> []^Node {
	count := 0
	for c := n.first_child; c != nil; c = c.next {
		if c.computed.position == .Flow {
			count += 1
		}
	}
	if count == 0 {
		return nil
	}

	items := make([]^Node, count, ctx.frame_allocator)
	at := 0
	for c := n.first_child; c != nil; c = c.next {
		if c.computed.position != .Flow {
			continue
		}
		items[at] = c
		at += 1
	}

	for i in 1 ..< count {
		c := items[i]
		j := i - 1
		for j >= 0 && items[j].computed.order > c.computed.order {
			items[j + 1] = items[j]
			j -= 1
		}
		items[j + 1] = c
	}
	return items
}

@(private)
break_lines :: proc(
	ctx: ^Context,
	items: []^Node,
	extent: f32,
	bounded: bool,
	ax: Axis,
	wrap: Wrap,
	gap: f32,
) -> []Line {
	mi := int(ax)
	lines := make([dynamic]Line, 0, 4, ctx.frame_allocator)
	cur: Line

	for c, i in items {
		outer := c.lay.size[mi] + edge_total(c.computed.margin, ax)
		add := cur.count == 0 ? outer : outer + gap
		if wrap != .None && bounded && cur.count > 0 && cur.main + add > extent + LAYOUT_EPS {
			append(&lines, cur)
			cur = Line {
				first = i,
				count = 1,
				main  = outer,
			}
			continue
		}
		cur.count += 1
		cur.main += add
	}
	append(&lines, cur)
	return lines[:]
}

@(private)
distribute :: proc(row: []^Node, ax: Axis, extent, gap: f32, shrink: bool) {
	mi := int(ax)
	total_gap := len(row) > 1 ? gap * f32(len(row) - 1) : 0

	for c in row {
		c.lay.frozen = false
	}

	for _ in 0 ..< DISTRIBUTE_ROUNDS {
		used := total_gap
		for c in row {
			used += c.lay.size[mi] + edge_total(c.computed.margin, ax)
		}
		free := extent - used
		if abs(free) < LAYOUT_EPS {
			return
		}
		if free < 0 && !shrink {
			return
		}

		share: f32
		for c in row {
			if c.lay.frozen {
				continue
			}
			if free > 0 {
				if g, ok := size_grow(axis_size(&c.computed, ax)); ok {
					share += g
				}
			} else {
				share += c.lay.size[mi]
			}
		}
		if share <= 0 {
			return
		}

		clamped := false
		for c in row {
			if c.lay.frozen {
				continue
			}

			weight: f32
			if free > 0 {
				g, ok := size_grow(axis_size(&c.computed, ax))
				if !ok {
					continue
				}
				weight = g
			} else {
				weight = c.lay.size[mi]
			}

			want := c.lay.size[mi] + free * (weight / share)
			got := axis_clamp(want, &c.computed, ax)
			if abs(got - want) > LAYOUT_EPS {
				c.lay.frozen = true
				clamped = true
			}
			c.lay.size[mi] = got
		}
		if !clamped {
			return
		}
	}
}

@(private)
place :: proc(ctx: ^Context, n: ^Node, origin: Vec2) {
	p := &n.computed
	n.rect = {origin.x, origin.y, n.lay.size.x, n.lay.size.y}

	inner := inner_edges(p)
	box := Vec2{max(n.rect.w - inner.l - inner.r, 0), max(n.rect.h - inner.t - inner.b, 0)}
	co := Vec2{n.rect.x + inner.l - n.scroll.x, n.rect.y + inner.t - n.scroll.y}

	content: Vec2
	for c := n.first_child; c != nil; c = c.next {
		cp := &c.computed
		if cp.position != .Flow {
			continue
		}
		place(ctx, c, {co.x + c.lay.pos.x, co.y + c.lay.pos.y})
		content.x = max(content.x, c.lay.pos.x + c.lay.size.x + cp.margin.r)
		content.y = max(content.y, c.lay.pos.y + c.lay.size.y + cp.margin.b)
	}
	n.content = content

	for c := n.first_child; c != nil; c = c.next {
		if c.computed.position != .Flow {
			place_out_of_flow(ctx, n, c)
		}
	}

	n.scroll.x = clamp(n.scroll.x, 0, max(content.x - box.x, 0))
	n.scroll.y = clamp(n.scroll.y, 0, max(content.y - box.y, 0))
}

@(private)
place_out_of_flow :: proc(ctx: ^Context, parent: ^Node, c: ^Node) {
	cp := &c.computed
	block := containing_block(ctx, parent, cp.position)

	known: [Axis]bool
	for a in Axis {
		i := int(a)
		lead := edge_lead(cp.inset, a)
		trail := edge_trail(cp.inset, a)
		room := i == 0 ? block.w : block.h

		if v, ok := definite_size(axis_size(cp, a), room, true); ok {
			c.lay.size[i] = axis_clamp(v, cp, a)
			known[a] = true
		} else if lead != 0 && trail != 0 {
			left := room - lead - trail - edge_total(cp.margin, a)
			c.lay.size[i] = axis_clamp(max(left, 0), cp, a)
			known[a] = true
		} else {
			c.lay.size[i] = c.lay.fit[i]
		}
	}

	layout_node(ctx, c, known)

	for a in Axis {
		i := int(a)
		lead := edge_lead(cp.inset, a)
		trail := edge_trail(cp.inset, a)
		room := i == 0 ? block.w : block.h

		if lead != 0 {
			c.lay.pos[i] = lead + edge_lead(cp.margin, a)
		} else if trail != 0 {
			c.lay.pos[i] = room - trail - edge_trail(cp.margin, a) - c.lay.size[i]
		} else {
			c.lay.pos[i] = edge_lead(cp.margin, a)
		}
	}

	place(ctx, c, {block.x + c.lay.pos.x, block.y + c.lay.pos.y})
}

@(private)
containing_block :: proc(ctx: ^Context, parent: ^Node, position: Position) -> Rect {
	if position == .Fixed {
		vp := ctx.input.viewport
		return {0, 0, vp.x, vp.y}
	}

	anc := parent
	for anc.parent != nil && anc.computed.position == .Flow {
		anc = anc.parent
	}

	b := anc.computed.border.width
	return {
		anc.rect.x + b.l,
		anc.rect.y + b.t,
		max(anc.rect.w - b.l - b.r, 0),
		max(anc.rect.h - b.t - b.b, 0),
	}
}
