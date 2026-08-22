package loom

import "base:runtime"
import "core:math"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

INPUT_PAD :: Edges{8, 6, 8, 6}
INPUT_RADIUS :: f32(6)
INPUT_MIN_W :: f32(40)
CARET_W :: f32(1)
BLINK_PERIOD :: f32(1.0)
UNDO_COALESCE :: f64(1.0)
UNDO_MAX :: 128

VIEW_KEY :: "view"
SEL_KEY :: "sel"
TXT_KEY :: "txt"
CARET_KEY :: "car"

Edit_Kind :: enum u8 {
	None,
	Insert,
	Delete_Back,
	Delete_Fwd,
	Replace,
	Paste,
}

Edit :: struct {
	at:            int,
	before:        string,
	after:         string,
	caret_before:  int,
	anchor_before: int,
	caret_after:   int,
	anchor_after:  int,
	kind:          Edit_Kind,
}

Input_State :: struct {
	caret:     int,
	anchor:    int,
	scroll_x:  f32,
	blink:     f32,
	undo:      [dynamic]Edit,
	redo:      [dynamic]Edit,
	last_kind: Edit_Kind,
	last_time: f64,
	moved:     bool,
	dragging:  bool,
	word_drag: bool,
	word_lo:   int,
	word_hi:   int,
}

buf_set :: proc(dst: ^[dynamic]byte, s: string) {
	clear(dst)
	append(dst, s)
}

buf_text :: proc(buf: ^[dynamic]byte) -> string {
	if buf == nil || len(buf) == 0 {
		return ""
	}
	return string(buf[:])
}

@(private)
rune_align :: proc(s: string, at: int) -> int {
	i := clamp(at, 0, len(s))
	for i > 0 && i < len(s) && (s[i] & 0xC0) == 0x80 {
		i -= 1
	}
	return i
}

@(private)
rune_prev :: proc(s: string, at: int) -> int {
	i := rune_align(s, at)
	if i <= 0 {
		return 0
	}
	_, n := utf8.decode_last_rune_in_string(s[:i])
	return max(i - n, 0)
}

@(private)
rune_next :: proc(s: string, at: int) -> int {
	i := rune_align(s, at)
	if i >= len(s) {
		return len(s)
	}
	_, n := utf8.decode_rune_in_string(s[i:])
	return min(i + n, len(s))
}

@(private)
Char_Class :: enum u8 {
	Space,
	Word,
	Punct,
}

@(private)
class_of :: proc(r: rune) -> Char_Class {
	if unicode.is_space(r) {
		return .Space
	}
	if unicode.is_letter(r) || unicode.is_digit(r) || r == '_' {
		return .Word
	}
	return .Punct
}

@(private)
class_before :: proc(s: string, at: int) -> Char_Class {
	if at <= 0 {
		return .Space
	}
	r, _ := utf8.decode_last_rune_in_string(s[:at])
	return class_of(r)
}

@(private)
class_after :: proc(s: string, at: int) -> Char_Class {
	if at >= len(s) {
		return .Space
	}
	r, _ := utf8.decode_rune_in_string(s[at:])
	return class_of(r)
}

@(private)
word_left :: proc(s: string, at: int) -> int {
	i := rune_align(s, at)
	for i > 0 && class_before(s, i) == .Space {
		i = rune_prev(s, i)
	}
	if i == 0 {
		return 0
	}
	c := class_before(s, i)
	for i > 0 && class_before(s, i) == c {
		i = rune_prev(s, i)
	}
	return i
}

@(private)
word_right :: proc(s: string, at: int) -> int {
	i := rune_align(s, at)
	if i >= len(s) {
		return len(s)
	}
	c := class_after(s, i)
	if c != .Space {
		for i < len(s) && class_after(s, i) == c {
			i = rune_next(s, i)
		}
	}
	for i < len(s) && class_after(s, i) == .Space {
		i = rune_next(s, i)
	}
	return i
}

@(private)
input_style :: proc(ctx: ^Context, n: ^Node) -> Text_Style {
	p := n.el.props
	if n.parent != nil {
		inherit_props(&p, &n.parent.computed)
	}
	inherit_props(&p, &ctx.cfg.root)
	return text_style(ctx, &p)
}

@(private)
caret_x :: proc(ctx: ^Context, style: Text_Style, s: string, at: int) -> f32 {
	i := rune_align(s, at)
	if i <= 0 {
		return 0
	}
	return measure_run(ctx, style, s[:i])
}

@(private)
offset_at :: proc(ctx: ^Context, style: Text_Style, s: string, x: f32) -> int {
	if len(s) == 0 || x <= 0 {
		return 0
	}
	starts := rune_starts(ctx, s)
	lo, hi := 0, len(starts) - 1
	for lo < hi {
		mid := (lo + hi + 1) / 2
		if measure_run(ctx, style, s[:starts[mid]]) <= x {
			lo = mid
		} else {
			hi = mid - 1
		}
	}
	if lo + 1 < len(starts) {
		a := measure_run(ctx, style, s[:starts[lo]])
		b := measure_run(ctx, style, s[:starts[lo + 1]])
		if x - a > b - x {
			return starts[lo + 1]
		}
	}
	return starts[lo]
}

@(private)
input_state_free :: proc(data: rawptr, allocator: runtime.Allocator) {
	st := (^Input_State)(data)
	edits_free(&st.undo, allocator)
	edits_free(&st.redo, allocator)
}

@(private)
edits_free :: proc(list: ^[dynamic]Edit, allocator: runtime.Allocator) {
	if list^ == nil {
		return
	}
	for &e in list {
		edit_free(&e, allocator)
	}
	delete(list^)
	list^ = nil
}

@(private)
edit_free :: proc(e: ^Edit, allocator: runtime.Allocator) {
	if e.before != "" {
		delete(e.before, allocator)
	}
	if e.after != "" {
		delete(e.after, allocator)
	}
	e.before, e.after = "", ""
}

@(private)
edits_clear :: proc(ctx: ^Context, list: ^[dynamic]Edit) {
	if list^ == nil {
		return
	}
	for &e in list {
		edit_free(&e, ctx.allocator)
	}
	clear(list)
}

@(private)
sel_range :: proc(st: ^Input_State) -> (lo: int, hi: int) {
	return min(st.caret, st.anchor), max(st.caret, st.anchor)
}

@(private)
Input_Ops :: struct {
	ctx:     ^Context,
	buf:     ^[dynamic]byte,
	st:      ^Input_State,
	changed: bool,
}

@(private)
apply_splice :: proc(buf: ^[dynamic]byte, lo, hi: int, insert: string) {
	old := len(buf)
	grow := len(insert) - (hi - lo)
	if grow > 0 {
		resize(buf, old + grow)
		copy(buf[lo + len(insert):], buf[hi:old])
	} else if grow < 0 {
		copy(buf[lo + len(insert):], buf[hi:old])
		resize(buf, old + grow)
	}
	if len(insert) > 0 {
		copy(buf[lo:], insert)
	}
}

@(private)
coalesces :: proc(op: ^Input_Ops, e: Edit) -> bool {
	st := op.st
	if len(st.undo) == 0 || st.moved || e.kind != st.last_kind {
		return false
	}
	if e.kind != .Insert && e.kind != .Delete_Back {
		return false
	}
	if op.ctx.time - st.last_time > UNDO_COALESCE {
		return false
	}
	top := st.undo[len(st.undo) - 1]
	if e.kind == .Insert {
		return top.before == "" && e.before == "" && e.at == top.at + len(top.after)
	}
	return top.after == "" && e.after == "" && e.at + len(e.before) == top.at
}

@(private)
push_edit :: proc(op: ^Input_Ops, e: Edit) {
	ctx := op.ctx
	st := op.st

	if st.undo == nil {
		st.undo = make([dynamic]Edit, 0, 8, ctx.allocator)
	}
	if st.redo == nil {
		st.redo = make([dynamic]Edit, 0, 8, ctx.allocator)
	}
	edits_clear(ctx, &st.redo)

	entry := e
	if coalesces(op, entry) {
		top := &st.undo[len(st.undo) - 1]
		if entry.kind == .Insert {
			joined := strings.concatenate({top.after, entry.after}, ctx.allocator)
			delete(top.after, ctx.allocator)
			top.after = joined
		} else {
			joined := strings.concatenate({entry.before, top.before}, ctx.allocator)
			delete(top.before, ctx.allocator)
			top.before = joined
			top.at = entry.at
		}
		edit_free(&entry, ctx.allocator)
		return
	}

	append(&st.undo, entry)
	for len(st.undo) > UNDO_MAX {
		edit_free(&st.undo[0], ctx.allocator)
		ordered_remove(&st.undo, 0)
	}
}

@(private)
splice :: proc(op: ^Input_Ops, at, remove: int, insert: string, kind: Edit_Kind) {
	ctx := op.ctx
	st := op.st
	s := buf_text(op.buf)
	lo := rune_align(s, clamp(at, 0, len(s)))
	hi := rune_align(s, clamp(at + remove, lo, len(s)))
	if lo == hi && insert == "" {
		return
	}

	entry := Edit {
		at            = lo,
		before        = strings.clone(s[lo:hi], ctx.allocator),
		after         = strings.clone(insert, ctx.allocator),
		caret_before  = st.caret,
		anchor_before = st.anchor,
		kind          = kind,
	}

	apply_splice(op.buf, lo, hi, insert)
	st.caret = lo + len(insert)
	st.anchor = st.caret
	entry.caret_after = st.caret
	entry.anchor_after = st.caret

	push_edit(op, entry)

	st.last_kind = kind
	st.last_time = ctx.time
	st.moved = false
	st.blink = 0
	op.changed = true
}

@(private)
undo_step :: proc(op: ^Input_Ops, from, to: ^[dynamic]Edit) {
	if len(from) == 0 {
		return
	}
	ctx := op.ctx
	st := op.st
	e := pop(from)

	apply_splice(op.buf, e.at, e.at + len(e.after), e.before)
	s := buf_text(op.buf)
	st.caret = rune_align(s, e.caret_before)
	st.anchor = rune_align(s, e.anchor_before)

	if to^ == nil {
		to^ = make([dynamic]Edit, 0, 8, ctx.allocator)
	}
	append(
		to,
		Edit {
			at = e.at,
			before = e.after,
			after = e.before,
			caret_before = e.caret_after,
			anchor_before = e.anchor_after,
			caret_after = e.caret_before,
			anchor_after = e.anchor_before,
			kind = e.kind,
		},
	)

	st.last_kind = .None
	st.moved = true
	st.blink = 0
	op.changed = true
}

@(private)
delete_selection :: proc(op: ^Input_Ops, kind: Edit_Kind) -> bool {
	lo, hi := sel_range(op.st)
	if lo == hi {
		return false
	}
	splice(op, lo, hi - lo, "", kind)
	return true
}

@(private)
filter_text :: proc(ctx: ^Context, s: string) -> string {
	clean := true
	for r in s {
		if r < 0x20 || r == 0x7f {
			clean = false
			break
		}
	}
	if clean {
		return s
	}
	b := strings.builder_make(0, len(s), ctx.frame_allocator)
	for r in s {
		if r >= 0x20 && r != 0x7f {
			strings.write_rune(&b, r)
		}
	}
	return strings.to_string(b)
}

@(private)
move_caret :: proc(st: ^Input_State, to: int, keep: bool) {
	st.caret = to
	if !keep {
		st.anchor = to
	}
	st.moved = true
	st.blink = 0
}

@(private)
hit_offset :: proc(op: ^Input_Ops, style: Text_Style, view_x: f32) -> int {
	ctx := op.ctx
	return offset_at(ctx, style, buf_text(op.buf), ctx.input.mouse.x - view_x + op.st.scroll_x)
}

input :: proc(
	buf: ^[dynamic]byte,
	el: Element = {},
	placeholder: string = "",
	loc := #caller_location,
) -> Interaction {
	ctx := ctx_of(loc)
	t := &ctx.theme

	e := Element {
		flags = {.Clickable, .Focusable, .Text_Input},
		props = {
			w = Grow(1),
			h = FIT,
			min_w = INPUT_MIN_W,
			dir = .Row,
			align = .Center,
			pad = INPUT_PAD,
			bg = t.surface,
			radius = rad(INPUT_RADIUS),
			border = {width = all(1), color = t.border},
			cursor = .Text,
		},
		hover = {border = {color = t.text_faint}},
		focus = {border = {color = t.accent}},
		disabled = {bg = t.raised, color = t.text_faint, cursor = .Not_Allowed},
	}
	merge_element(&e, el, loc)

	it := begin(e, loc)
	st := state_dtor(Input_State, input_state_free, loc)
	live := .Disabled not_in e.flags && .Disabled not_in it.state

	s := buf_text(buf)
	st.caret = rune_align(s, st.caret)
	st.anchor = rune_align(s, st.anchor)

	style := input_style(ctx, it.node)
	view := node_alive(ctx, hash_string(it.id, VIEW_KEY))
	view_w := view != nil ? view.rect.w : 0
	view_x := view != nil ? view.rect.x : 0

	op := Input_Ops {
		ctx = ctx,
		buf = buf,
		st  = st,
	}

	if live {
		input_mouse(&op, it, style, view_x)
		if it.focused {
			input_keys(&op, style)
		}
	}
	if !it.focused && st.dragging {
		st.dragging = false
		st.word_drag = false
		capture_mouse(0)
	}

	s = buf_text(buf)
	st.caret = rune_align(s, st.caret)
	st.anchor = rune_align(s, st.anchor)

	cx := caret_x(ctx, style, s, st.caret)
	if view_w > 0 {
		total := measure_run(ctx, style, s)
		if cx - st.scroll_x < 0 {
			st.scroll_x = cx
		}
		if cx - st.scroll_x > view_w - CARET_W {
			st.scroll_x = cx - view_w + CARET_W
		}
		st.scroll_x = clamp(st.scroll_x, 0, max(total - view_w, 0))
	} else {
		st.scroll_x = 0
	}

	blink_on := true
	if it.focused {
		st.blink += ctx.input.dt
		blink_on = math.mod(st.blink, BLINK_PERIOD) < BLINK_PERIOD * 0.5
		request_frame(loc)
	}

	lo, hi := sel_range(st)
	sel_lo := caret_x(ctx, style, s, lo)
	sel_hi := caret_x(ctx, style, s, hi)
	empty := len(s) == 0

	begin(
		{
			key = VIEW_KEY,
			flags = {.Clip, .Pass_Through},
			props = {w = Grow(1), h = FIT, position = .Relative},
		},
		loc,
	)

	leaf(
		{
			key = SEL_KEY,
			props = {
				position = .Absolute,
				inset = {l = sel_lo - st.scroll_x},
				w = Px(it.focused ? sel_hi - sel_lo : 0),
				h = Pct(100),
				bg = t.selection,
			},
		},
		loc,
	)

	leaf(
		{
			key = TXT_KEY,
			text = empty ? placeholder : s,
			props = {
				w = FIT,
				h = FIT,
				margin = {l = -st.scroll_x},
				text_wrap = .None,
				color = empty ? t.text_faint : nil,
			},
		},
		loc,
	)

	leaf(
		{
			key = CARET_KEY,
			props = {
				position = .Absolute,
				inset = {l = cx - st.scroll_x},
				w = Px(CARET_W),
				h = Pct(100),
				bg = t.text,
				opacity = it.focused && blink_on ? 1 : 0,
			},
		},
		loc,
	)

	end()
	end()

	it.changed = op.changed
	it.state = it.node.state
	return it
}

@(private)
input_mouse :: proc(op: ^Input_Ops, it: Interaction, style: Text_Style, view_x: f32) {
	ctx := op.ctx
	st := op.st

	if it.pressed && .Left in ctx.input.mouse_pressed {
		move_caret(st, hit_offset(op, style, view_x), .Shift in ctx.input.mods)
		st.dragging = true
		st.word_drag = false
		capture_mouse(it.id)
	}

	if it.double_clicked {
		s := buf_text(op.buf)
		at := hit_offset(op, style, view_x)
		st.word_lo = word_left(s, rune_next(s, at))
		st.word_hi = word_right(s, at)
		st.anchor = st.word_lo
		st.caret = st.word_hi
		st.word_drag = true
		st.moved = true
		st.blink = 0
	}

	if !st.dragging {
		return
	}

	if .Left not_in ctx.input.mouse_down {
		st.dragging = false
		st.word_drag = false
		capture_mouse(0)
		return
	}

	s := buf_text(op.buf)
	at := hit_offset(op, style, view_x)
	if st.word_drag {
		if at < st.word_lo {
			st.anchor = st.word_hi
			st.caret = word_left(s, rune_next(s, at))
		} else {
			st.anchor = st.word_lo
			st.caret = word_right(s, at)
		}
	} else {
		st.caret = at
	}
	st.moved = true
	st.blink = 0
}

@(private)
input_keys :: proc(op: ^Input_Ops, style: Text_Style) {
	ctx := op.ctx
	st := op.st
	ctrl := .Ctrl in ctx.input.mods
	shift := .Shift in ctx.input.mods

	if key_pressed(.Left) {
		s := buf_text(op.buf)
		lo, hi := sel_range(st)
		to := ctrl ? word_left(s, st.caret) : (!shift && lo != hi ? lo : rune_prev(s, st.caret))
		move_caret(st, to, shift)
	}
	if key_pressed(.Right) {
		s := buf_text(op.buf)
		lo, hi := sel_range(st)
		to := ctrl ? word_right(s, st.caret) : (!shift && lo != hi ? hi : rune_next(s, st.caret))
		move_caret(st, to, shift)
	}
	if key_pressed(.Home) {
		move_caret(st, 0, shift)
	}
	if key_pressed(.End) {
		move_caret(st, len(buf_text(op.buf)), shift)
	}

	if ctrl && key_pressed(.A) {
		st.anchor = 0
		st.caret = len(buf_text(op.buf))
		st.moved = true
		st.blink = 0
	}

	if ctrl && (key_pressed(.C) || key_pressed(.X)) {
		s := buf_text(op.buf)
		lo, hi := sel_range(st)
		if lo != hi {
			set_clipboard_text(s[lo:hi])
			if key_pressed(.X) {
				delete_selection(op, .Replace)
			}
		}
	}

	if ctrl && key_pressed(.V) {
		paste := filter_text(ctx, clipboard_text())
		if paste != "" {
			lo, hi := sel_range(st)
			splice(op, lo, hi - lo, paste, .Paste)
		}
	}

	if ctrl && key_pressed(.Z) {
		if shift {
			undo_step(op, &st.redo, &st.undo)
		} else {
			undo_step(op, &st.undo, &st.redo)
		}
	}
	if ctrl && key_pressed(.Y) {
		undo_step(op, &st.redo, &st.undo)
	}

	if key_pressed(.Backspace) {
		if !delete_selection(op, .Replace) {
			s := buf_text(op.buf)
			from := ctrl ? word_left(s, st.caret) : rune_prev(s, st.caret)
			if from < st.caret {
				splice(op, from, st.caret - from, "", .Delete_Back)
			}
		}
	}
	if key_pressed(.Delete) {
		if !delete_selection(op, .Replace) {
			s := buf_text(op.buf)
			to := ctrl ? word_right(s, st.caret) : rune_next(s, st.caret)
			if to > st.caret {
				splice(op, st.caret, to - st.caret, "", .Delete_Fwd)
			}
		}
	}

	if !ctrl {
		typed := filter_text(ctx, ctx.input.text)
		if typed != "" {
			lo, hi := sel_range(st)
			splice(op, lo, hi - lo, typed, lo != hi ? .Replace : .Insert)
		}
	}
}
