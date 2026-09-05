package loom

import "core:hash"
import "core:math"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

ELLIPSIS :: "…"

@(private)
Text_Style :: struct {
	font:    Font,
	size:    f32,
	spacing: f32,
	wrap:    Text_Wrap,
	align:   Text_Align,
	line_h:  f32,
	ascent:  f32,
	tab_w:   f32,
	tab_org: f32,
}

@(private)
Text_Key :: struct {
	font:    Font,
	size:    f32,
	spacing: f32,
	max_w:   f32,
	wrap:    Text_Wrap,
	tab_w:   f32,
	tab_org: f32,
	hash:    u64,
	n:       int,
}

@(private)
Text_Word :: struct {
	start, end: int,
	width:      f32,
}

@(private)
Text_Line :: struct {
	first_word: int,
	word_count: int,
	start, end: int,
	width:      f32,
	hard_break: bool,
}

@(private)
Text_Entry :: struct {
	text:      string,
	words:     []Text_Word,
	lines:     []Text_Line,
	size:      Vec2,
	space_w:   f32,
	last_used: u64,
}

// A colour run over a node's text, by byte.
Text_Span :: struct {
	start, end: int,
	color:      Color,
}

Text_Run :: struct {
	pos:   Vec2,
	text:  string,
	width: f32,
	// Unset when the run takes the node's own colour.
	color: Maybe(Color),
}

text_runs :: proc(n: ^Node) -> []Text_Run {
	if n == nil || n.lay == nil {
		return nil
	}
	return n.lay.runs
}

@(private)
text_style :: proc(ctx: ^Context, p: ^Props) -> Text_Style {
	m := text_metrics(ctx, p)
	st := Text_Style {
		font    = p.font,
		size    = p.font_size,
		spacing = p.letter_spacing,
		wrap    = p.text_wrap,
		align   = p.text_align,
		ascent  = m.ascent,
		tab_w   = p.tab_size,
		tab_org = p.tab_origin,
	}
	st.line_h = p.line_height > 0 ? p.line_height * p.font_size : m.ascent - m.descent + m.line_gap
	return st
}

@(private)
text_metrics :: proc(ctx: ^Context, p: ^Props) -> Font_Metrics {
	fm := ctx.cfg.backend.font_metrics
	if fm == nil {
		return {}
	}
	return fm(p.font, p.font_size, ctx.cfg.backend.user)
}

@(private)
text_line_height :: proc(ctx: ^Context, p: ^Props) -> f32 {
	return text_style(ctx, p).line_h
}

@(private)
text_ascent :: proc(ctx: ^Context, p: ^Props) -> f32 {
	return text_style(ctx, p).ascent
}

// The next tab stop at or after `x`, on the grid of `size` that starts at
// `origin`. A tab always advances, so a pen already on a stop moves to the next.
@(private)
tab_stop :: proc(x, origin, size: f32) -> f32 {
	if size <= 0 {
		return x
	}
	steps := math.floor((x - origin) / size) + 1
	return origin + steps * size
}

@(private)
measure_plain :: proc(ctx: ^Context, st: Text_Style, s: string) -> f32 {
	if s == "" {
		return 0
	}
	mr := ctx.cfg.backend.measure_run
	if mr == nil {
		return 0
	}
	ctx.text_measures += 1
	return mr(st.font, st.size, s, st.spacing, ctx.cfg.backend.user)
}

// Measures `s` with every tab advanced to its stop. The grid is anchored at the
// node's own left edge, and `tab_origin` is the pen x at which `s` starts, so
// a caller that measures a line in pieces keeps every piece on one grid.
@(private)
measure_tabbed :: proc(ctx: ^Context, st: Text_Style, s: string) -> f32 {
	x := st.tab_org
	i := 0
	for i < len(s) {
		j := i
		for j < len(s) && s[j] != '\t' {
			j += 1
		}
		x += measure_plain(ctx, st, s[i:j])
		if j >= len(s) {
			break
		}
		x = tab_stop(x, 0, st.tab_w)
		i = j + 1
	}
	return x - st.tab_org
}

@(private)
measure_run :: proc(ctx: ^Context, st: Text_Style, s: string) -> f32 {
	if s == "" {
		return 0
	}
	if st.tab_w > 0 {
		return measure_tabbed(ctx, st, s)
	}
	return measure_plain(ctx, st, s)
}

@(private)
measure_text_node :: proc(ctx: ^Context, n: ^Node, max_w: f32) -> Vec2 {
	if n.el.text == "" {
		return {}
	}
	st := text_style(ctx, &n.computed)
	e := text_layout(ctx, st, n.el.text, max(max_w, 0))
	return e.size
}

measure :: proc(text: string, props: Props, max_w: f32 = 0, loc := #caller_location) -> Vec2 {
	ctx := ctx_of(loc)
	if text == "" {
		return {}
	}

	p := props
	if n := current(); n != nil {
		inherit_props(&p, &n.computed)
	}
	inherit_props(&p, &ctx.cfg.root)

	st := text_style(ctx, &p)
	e := text_layout(ctx, st, text, max(max_w, 0))
	return e.size
}

text_width :: proc(text: string, props: Props = {}, loc := #caller_location) -> f32 {
	ctx := ctx_of(loc)
	if text == "" {
		return 0
	}

	p := props
	if n := current(); n != nil {
		inherit_props(&p, &n.computed)
	}
	inherit_props(&p, &ctx.cfg.root)

	return measure_run(ctx, text_style(ctx, &p), text)
}

@(private)
text_key :: proc(st: Text_Style, text: string, max_w: f32) -> Text_Key {
	return Text_Key {
		font = st.font,
		size = st.size,
		spacing = st.spacing,
		max_w = max_w,
		wrap = st.wrap,
		tab_w = st.tab_w,
		tab_org = st.tab_org,
		hash = hash.fnv64a(transmute([]u8)text),
		n = len(text),
	}
}

@(private)
text_layout :: proc(ctx: ^Context, st: Text_Style, text: string, max_w: f32) -> Text_Entry {
	key := text_key(st, text, max_w)

	if e, ok := &ctx.text_cache[key]; ok {
		if e.text == text {
			e.last_used = ctx.frame_index
			ctx.text_hits += 1
			return e^
		}
		free_text_entry(ctx, e)
		delete_key(&ctx.text_cache, key)
	}

	ctx.text_misses += 1
	e := build_text_entry(ctx, st, text, max_w)
	ctx.text_cache[key] = e
	return e
}

@(private)
free_text_entry :: proc(ctx: ^Context, e: ^Text_Entry) {
	delete(e.text, ctx.allocator)
	delete(e.words, ctx.allocator)
	delete(e.lines, ctx.allocator)
	e^ = {}
}

@(private)
build_text_entry :: proc(ctx: ^Context, st: Text_Style, text: string, max_w: f32) -> Text_Entry {
	words := make([dynamic]Text_Word, 0, 16, ctx.frame_allocator)
	lines := make([dynamic]Text_Line, 0, 4, ctx.frame_allocator)
	space_w: f32

	switch st.wrap {
	case .Words:
		space_w = wrap_words(ctx, st, text, max_w, &words, &lines)
	case .None:
		wrap_single(ctx, st, text, &words, &lines)
	case .Chars:
		wrap_chars(ctx, st, text, max_w, &words, &lines)
	case .Ellipsis:
		wrap_ellipsis(ctx, st, text, max_w, &words, &lines)
	}

	e := Text_Entry {
		text      = strings.clone(text, ctx.allocator),
		words     = slice.clone(words[:], ctx.allocator),
		lines     = slice.clone(lines[:], ctx.allocator),
		space_w   = space_w,
		last_used = ctx.frame_index,
	}

	for ln in e.lines {
		e.size.x = max(e.size.x, ln.width)
	}
	e.size.y = f32(len(e.lines)) * st.line_h
	return e
}

@(private)
push_text_line :: proc(
	words: ^[dynamic]Text_Word,
	lines: ^[dynamic]Text_Line,
	first, count: int,
	width: f32,
	at: int,
	hard: bool,
) {
	ln := Text_Line {
		first_word = first,
		word_count = count,
		start      = at,
		end        = at,
		width      = width,
		hard_break = hard,
	}
	if count > 0 {
		ln.start = words[first].start
		ln.end = words[first + count - 1].end
	}
	append(lines, ln)
}

@(private)
wrap_words :: proc(
	ctx: ^Context,
	st: Text_Style,
	text: string,
	max_w: f32,
	words: ^[dynamic]Text_Word,
	lines: ^[dynamic]Text_Line,
) -> f32 {
	space_w := measure_run(ctx, st, " ")
	limit := max_w + LAYOUT_EPS

	first, count := 0, 0
	cur: f32
	at := 0

	i := 0
	for {
		j := i
		for j < len(text) && text[j] != ' ' && text[j] != '\n' {
			j += 1
		}

		if j > i {
			w := measure_run(ctx, st, text[i:j])
			add := count > 0 ? space_w + w : w
			if count > 0 && max_w > 0 && cur + add > limit {
				push_text_line(words, lines, first, count, cur, at, false)
				first, count, cur, at = len(words), 0, 0, i
				add = w
			}
			append(words, Text_Word{start = i, end = j, width = w})
			cur += add
			count += 1
		}

		if j >= len(text) {
			push_text_line(words, lines, first, count, cur, at, true)
			break
		}

		if text[j] == '\n' {
			push_text_line(words, lines, first, count, cur, at, true)
			first, count, cur, at = len(words), 0, 0, j + 1
		}
		i = j + 1
	}
	return space_w
}

@(private)
wrap_single :: proc(
	ctx: ^Context,
	st: Text_Style,
	text: string,
	words: ^[dynamic]Text_Word,
	lines: ^[dynamic]Text_Line,
) {
	w := measure_run(ctx, st, text)
	append(words, Text_Word{start = 0, end = len(text), width = w})
	push_text_line(words, lines, 0, 1, w, 0, true)
}

@(private)
wrap_chars :: proc(
	ctx: ^Context,
	st: Text_Style,
	text: string,
	max_w: f32,
	words: ^[dynamic]Text_Word,
	lines: ^[dynamic]Text_Line,
) {
	limit := max_w + LAYOUT_EPS
	start := 0
	cur: f32
	any_rune := false

	flush :: proc(
		ctx: ^Context,
		st: Text_Style,
		text: string,
		words: ^[dynamic]Text_Word,
		lines: ^[dynamic]Text_Line,
		from, to: int,
		hard: bool,
	) {
		if to > from {
			w := measure_run(ctx, st, text[from:to])
			append(words, Text_Word{start = from, end = to, width = w})
			push_text_line(words, lines, len(words) - 1, 1, w, from, hard)
			return
		}
		push_text_line(words, lines, len(words), 0, 0, from, hard)
	}

	i := 0
	for i < len(text) {
		if text[i] == '\n' {
			flush(ctx, st, text, words, lines, start, i, true)
			i += 1
			start, cur, any_rune = i, 0, false
			continue
		}

		_, n := utf8.decode_rune_in_string(text[i:])
		if n <= 0 {
			n = 1
		}
		w := measure_run(ctx, st, text[i:i + n])
		if any_rune && max_w > 0 && cur + w > limit {
			flush(ctx, st, text, words, lines, start, i, false)
			start, cur, any_rune = i, 0, false
		}
		cur += w
		any_rune = true
		i += n
	}

	flush(ctx, st, text, words, lines, start, len(text), true)
}

@(private)
wrap_ellipsis :: proc(
	ctx: ^Context,
	st: Text_Style,
	text: string,
	max_w: f32,
	words: ^[dynamic]Text_Word,
	lines: ^[dynamic]Text_Line,
) {
	full := measure_run(ctx, st, text)
	if max_w <= 0 || full <= max_w + LAYOUT_EPS {
		append(words, Text_Word{start = 0, end = len(text), width = full})
		push_text_line(words, lines, 0, 1, full, 0, true)
		return
	}

	ell := measure_run(ctx, st, ELLIPSIS)
	avail := max_w - ell

	cut, cut_w := 0, f32(0)
	if avail > 0 {
		starts := rune_starts(ctx, text)
		lo, hi := 0, len(starts) - 1
		for lo <= hi {
			mid := (lo + hi) / 2
			w := measure_run(ctx, st, text[:starts[mid]])
			if w <= avail + LAYOUT_EPS {
				cut, cut_w = starts[mid], w
				lo = mid + 1
			} else {
				hi = mid - 1
			}
		}
	}

	first := len(words)
	count := 0
	if cut > 0 {
		append(words, Text_Word{start = 0, end = cut, width = cut_w})
		count += 1
	}
	append(words, Text_Word{start = -1, end = -1, width = ell})
	count += 1

	push_text_line(words, lines, first, count, cut_w + ell, 0, true)
	lines[len(lines) - 1].start = 0
	lines[len(lines) - 1].end = cut
}

@(private)
rune_starts :: proc(ctx: ^Context, text: string) -> []int {
	out := make([dynamic]int, 0, len(text) + 1, ctx.frame_allocator)
	i := 0
	for i < len(text) {
		append(&out, i)
		_, n := utf8.decode_rune_in_string(text[i:])
		if n <= 0 {
			n = 1
		}
		i += n
	}
	append(&out, len(text))
	return out[:]
}

// The colour covering byte `at`, and the next boundary at or before `limit`.
// `cursor` walks forward over the spans, so a whole line costs one pass.
@(private)
span_at :: proc(spans: []Text_Span, cursor: ^int, at, limit: int) -> (col: Maybe(Color), edge: int) {
	edge = limit
	for cursor^ < len(spans) && spans[cursor^].end <= at {
		cursor^ += 1
	}
	if cursor^ >= len(spans) {
		return
	}
	s := spans[cursor^]
	if s.start > at {
		edge = min(edge, s.start)
		return
	}
	col = s.color
	edge = min(edge, s.end)
	return
}

// Appends the runs of `text[from:to]`, cut at every tab and every colour-span
// edge, and reports the pen x after them. `grid` is the x the stops are anchored
// at, the left edge of the line. `width` skips the measure when it is known.
@(private)
push_text_run :: proc(
	ctx: ^Context,
	out: ^[dynamic]Text_Run,
	st: Text_Style,
	spans: []Text_Span,
	text: string,
	from, to: int,
	pen, y: f32,
	grid: f32,
	width: f32 = -1,
) -> f32 {
	if st.tab_w <= 0 && len(spans) == 0 {
		if to <= from {
			return pen
		}
		w := width >= 0 ? width : measure_plain(ctx, st, text[from:to])
		append(out, Text_Run{pos = {pen, y}, text = text[from:to], width = w})
		return pen + w
	}

	cursor := 0
	x := pen
	i := from
	for i < to {
		j := to
		if st.tab_w > 0 {
			for k := i; k < j; k += 1 {
				if text[k] == '\t' {
					j = k
					break
				}
			}
		}
		col, edge := span_at(spans, &cursor, i, j)
		j = min(j, edge)

		if j > i {
			w := measure_plain(ctx, st, text[i:j])
			append(out, Text_Run{pos = {x, y}, text = text[i:j], width = w, color = col})
			x += w
		}
		if j < to && st.tab_w > 0 && text[j] == '\t' {
			x = tab_stop(x, grid, st.tab_w)
			j += 1
		}
		i = j
	}
	return x
}

// The pen x of byte `at` inside `text`, measured from the start of the run.
caret_x :: proc(text: string, at: int, props: Props = {}, loc := #caller_location) -> f32 {
	ctx := ctx_of(loc)
	p := props
	if n := current(); n != nil {
		inherit_props(&p, &n.computed)
	}
	inherit_props(&p, &ctx.cfg.root)
	return caret_x_st(ctx, text_style(ctx, &p), text, at)
}

// The byte index of `text` nearest pixel `x`, measured from the start of the run.
offset_at :: proc(text: string, x: f32, props: Props = {}, loc := #caller_location) -> int {
	ctx := ctx_of(loc)
	p := props
	if n := current(); n != nil {
		inherit_props(&p, &n.computed)
	}
	inherit_props(&p, &ctx.cfg.root)
	return offset_at_st(ctx, text_style(ctx, &p), text, x)
}

@(private)
build_runs :: proc(ctx: ^Context, n: ^Node, origin: Vec2, box: Vec2) -> []Text_Run {
	st := text_style(ctx, &n.computed)
	e := text_layout(ctx, st, n.el.text, max(box.x, 0))
	if len(e.lines) == 0 {
		return nil
	}

	out := make([dynamic]Text_Run, 0, len(e.lines), ctx.frame_allocator)

	for ln, i in e.lines {
		if ln.word_count == 0 {
			continue
		}

		y := origin.y + f32(i) * st.line_h + st.ascent
		x := origin.x
		switch st.align {
		case .Start:
		case .Center:
			x += (box.x - ln.width) * 0.5
		case .End:
			x += box.x - ln.width
		case .Justify:
		}

		row := e.words[ln.first_word:][:ln.word_count]
		justify := st.align == .Justify && !ln.hard_break && ln.word_count > 1

		split := justify
		if !split {
			for w in row {
				if w.start < 0 {
					split = true
					break
				}
			}
		}

		if !split {
			push_text_run(
				ctx,
				&out,
				st,
				n.el.spans,
				e.text,
				ln.start,
				ln.end,
				x,
				y,
				x,
				ln.width,
			)
			continue
		}

		gap: f32
		if justify {
			gap = e.space_w + max((box.x - ln.width) / f32(ln.word_count - 1), 0)
		}

		cx := x
		for w in row {
			if w.start < 0 {
				append(&out, Text_Run{pos = {cx, y}, text = ELLIPSIS, width = w.width})
				cx += w.width + gap
				continue
			}
			cx =
				push_text_run(
					ctx,
					&out,
					st,
					n.el.spans,
					e.text,
					w.start,
					w.end,
					cx,
					y,
					x,
					w.width,
				) +
				gap
		}
	}

	return out[:]
}

@(private)
evict_text :: proc(ctx: ^Context) {
	if ctx.frame_index <= u64(ctx.cfg.text_cache_frames) {
		return
	}
	deadline := ctx.frame_index - u64(ctx.cfg.text_cache_frames)

	doomed := make([dynamic]Text_Key, 0, 8, ctx.frame_allocator)
	defer delete(doomed)

	for k, e in ctx.text_cache {
		if e.last_used < deadline {
			append(&doomed, k)
		}
	}

	for k in doomed {
		e := &ctx.text_cache[k]
		free_text_entry(ctx, e)
		delete_key(&ctx.text_cache, k)
	}
}

@(private)
free_text_cache :: proc(ctx: ^Context) {
	for _, &e in ctx.text_cache {
		free_text_entry(ctx, &e)
	}
	delete(ctx.text_cache)
	ctx.text_cache = {}
}
