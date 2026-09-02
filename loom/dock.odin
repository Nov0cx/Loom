package loom

import "base:runtime"
import ini "core:encoding/ini"
import "core:fmt"
import "core:strconv"
import "core:strings"

DOCK_TAB_H :: f32(26)
DOCK_SPLITTER :: f32(6)
DOCK_MIN_PANEL :: Vec2{80, 60}
DOCK_EDGE_FRAC :: f32(0.22)
DOCK_OUTER_BAND :: f32(24)
DOCK_FLOAT_SIZE :: Vec2{420, 300}
DOCK_TAB_PAD :: Edges{10, 4, 8, 4}
DOCK_TAB_GAP :: f32(2)
DOCK_CLOSE_W :: f32(14)
DOCK_RADIUS :: f32(4)

DOCK_SECTION :: "dock"
DOCK_BAR_KEY :: "loom.dockbar"
DOCK_SPLIT_KEY :: "loom.docksplit"
DOCK_DROP_KEY :: "loom.dockdrop"
DOCK_GHOST_KEY :: "loom.dockghost"

Dock_Mode :: enum u8 {
	In_Window,
	Detachable,
}

Dock_Side :: enum u8 {
	Left,
	Right,
	Top,
	Bottom,
}

Dock_Kind :: enum u8 {
	Tabs,
	Split,
}

Dock_Zone :: enum u8 {
	None,
	Center,
	Left,
	Right,
	Top,
	Bottom,
}

Dock_Id :: distinct u64

Dock_Config :: struct {
	mode:       Dock_Mode,
	tab_height: f32,
	splitter:   f32,
	min_panel:  Vec2,
}

Dock_Tab :: struct {
	title: string,
	open:  ^bool,
	seen:  u64,
}

Dock_Node :: struct {
	id:       Dock_Id,
	space:    ^Dock_Space,
	kind:     Dock_Kind,
	dir:      Direction,
	ratio:    f32,
	parent:   ^Dock_Node,
	children: [2]^Dock_Node,
	tabs:     [dynamic]Dock_Tab,
	active:   int,
	rect:     Rect,
	viewport: ^Viewport,
}

Dock_Space :: struct {
	id:       string,
	handle:   Dock_Id,
	cfg:      Dock_Config,
	root:     ^Dock_Node,
	detached: [dynamic]^Dock_Node,
	node:     ^Node,
	rect:     Rect,
	frame:    u64,
	pending:  map[string]string,
}

Dock_Action_Kind :: enum u8 {
	Close,
}

Dock_Action :: struct {
	kind:  Dock_Action_Kind,
	space: ^Dock_Space,
	node:  ^Dock_Node,
	title: string,
}

Dock_Drag :: struct {
	active: bool,
	frame:  u64,
	origin: ^Dock_Space,
	from:   ^Dock_Node,
	title:  string,
	space:  ^Dock_Space,
	target: ^Dock_Node,
	zone:   Dock_Zone,
	outer:  bool,
	rect:   Rect,
}

dockspace :: proc(
	id: string,
	cfg: Dock_Config = {},
	el: Element = {},
	loc := #caller_location,
) -> Dock_Id {
	ctx := ctx_of(loc)
	assert(id != "", "loom: a dockspace needs a non-empty id", loc)

	sp := dock_space_get(ctx, id)
	sp.cfg = dock_defaults(cfg)
	if viewport_ops(ctx) == nil {
		sp.cfg.mode = .In_Window
	}
	dock_apply_pending(ctx, sp)

	t := &ctx.theme
	e := Element {
		key   = id,
		props = {
			w = Grow(1),
			h = Grow(1),
			position = .Relative,
			bg = t.bg,
			overflow = {.Hidden, .Hidden},
		},
	}
	merge_element(&e, el, loc)

	it := begin(e, loc)
	sp.node = it.node
	sp.frame = ctx.frame_index
	append(&ctx.dock_order, sp)

	dock_ensure_root(ctx, sp)
	dock_resolve(ctx, sp)
	dock_fix_active(ctx, sp)

	dock_drag_reset(ctx)
	dock_chrome(ctx, sp, loc)
	dock_zone_scan(ctx, sp)
	dock_overlay(ctx, sp, loc)

	end()
	return sp.handle
}

panel :: proc(
	dock: Dock_Id,
	title: string,
	open: ^bool = nil,
	el: Element = {},
	loc := #caller_location,
) -> bool {
	ctx := ctx_of(loc)
	sp := dock_space_by_handle(ctx, dock)
	if sp == nil || title == "" {
		return false
	}

	if open != nil && !open^ {
		if n, _ := dock_find_anywhere(ctx, sp, title); n != nil {
			dock_queue_close(ctx, n.space, n, title)
		}
		return false
	}

	tn, idx := dock_find_anywhere(ctx, sp, title)
	if tn == nil {
		tn, idx = dock_insert_default(ctx, sp, title)
	}
	if tn == nil {
		return false
	}

	tab := &tn.tabs[idx]
	tab.open = open
	tab.seen = ctx.frame_index

	if idx != tn.active {
		return false
	}

	r := dock_body_rect(tn.space, tn)
	if tn.viewport != nil {
		tn.viewport.dock = tn
	}
	if r.w <= 0 || r.h <= 0 {
		return false
	}

	t := &ctx.theme
	e := Element {
		key   = title,
		flags = {.Clip},
		props = {
			position = .Fixed,
			inset = {l = r.x, t = r.y},
			w = Px(r.w),
			h = Px(r.h),
			dir = .Column,
			bg = t.surface,
			border = {width = all(1), color = t.border},
		},
	}
	merge_element(&e, el, loc)

	pit := begin(e, loc)
	pit.node.viewport = tn.viewport
	if tn.viewport != nil {
		tn.viewport.node = pit.node
	}
	return true
}

end_panel :: proc() {
	end()
}

dock_split :: proc(dock: Dock_Id, target: string, side: Dock_Side, ratio: f32) -> (a, b: Dock_Id) {
	ctx := ctx_of()
	sp := dock_space_by_handle(ctx, dock)
	if sp == nil {
		return 0, 0
	}
	dock_ensure_root(ctx, sp)

	tn: ^Dock_Node
	if target == "" {
		tn = sp.root
	} else {
		tn, _ = dock_find_tab(sp, target)
	}
	if tn == nil {
		tn = sp.root
	}

	first, second := dock_split_node(ctx, sp, tn, side, ratio)
	if first == nil {
		return 0, 0
	}
	mark_dirty(ctx)
	return first.id, second.id
}

dock_panel :: proc(dock: Dock_Id, title: string, into: Dock_Id) {
	ctx := ctx_of()
	sp := dock_space_by_handle(ctx, dock)
	if sp == nil || title == "" {
		return
	}
	dest, ok := ctx.dock_nodes[into]
	if !ok || dest.kind != .Tabs || dest.space != sp {
		return
	}

	if src, idx := dock_find_tab(sp, title); src != nil {
		if src == dest {
			return
		}
		tab := dock_take_tab(ctx, src, idx)
		dock_add_tab(ctx, dest, tab)
		dock_collapse(ctx, sp, src)
	} else {
		dock_add_tab(ctx, dest, Dock_Tab{title = strings.clone(title, ctx.allocator)})
	}
	mark_dirty(ctx)
}

dock_can_detach :: proc() -> bool {
	return has_viewports()
}

@(private)
dock_defaults :: proc(cfg: Dock_Config) -> Dock_Config {
	out := cfg
	if out.tab_height <= 0 {
		out.tab_height = DOCK_TAB_H
	}
	if out.splitter <= 0 {
		out.splitter = DOCK_SPLITTER
	}
	if out.min_panel.x <= 0 {
		out.min_panel.x = DOCK_MIN_PANEL.x
	}
	if out.min_panel.y <= 0 {
		out.min_panel.y = DOCK_MIN_PANEL.y
	}
	return out
}

@(private)
dock_space_get :: proc(ctx: ^Context, id: string) -> ^Dock_Space {
	if sp, ok := ctx.docks[id]; ok {
		return sp
	}
	sp, err := new(Dock_Space, ctx.allocator)
	assert(err == nil, "loom: out of memory allocating a dockspace")
	sp.id = strings.clone(id, ctx.allocator)
	sp.handle = Dock_Id(hash_string(0, id))
	sp.detached = make([dynamic]^Dock_Node, 0, 2, ctx.allocator)
	sp.pending = make(map[string]string, 8, ctx.allocator)
	ctx.docks[sp.id] = sp
	dock_register_handler(ctx)
	return sp
}

@(private)
dock_space_by_handle :: proc(ctx: ^Context, h: Dock_Id) -> ^Dock_Space {
	for _, sp in ctx.docks {
		if sp.handle == h {
			return sp
		}
	}
	return nil
}

@(private)
dock_new_node :: proc(ctx: ^Context, sp: ^Dock_Space, kind: Dock_Kind) -> ^Dock_Node {
	n, err := new(Dock_Node, ctx.allocator)
	assert(err == nil, "loom: out of memory allocating a dock node")
	ctx.dock_serial += 1
	n.id = Dock_Id(hash_int(Id(sp.handle), i64(ctx.dock_serial)))
	n.space = sp
	n.kind = kind
	n.ratio = 0.5
	n.tabs = make([dynamic]Dock_Tab, 0, 4, ctx.allocator)
	ctx.dock_nodes[n.id] = n
	return n
}

@(private)
dock_free_node :: proc(ctx: ^Context, n: ^Dock_Node) {
	for tab in n.tabs {
		delete(tab.title, ctx.allocator)
	}
	delete(n.tabs)
	delete_key(&ctx.dock_nodes, n.id)
	free(n, ctx.allocator)
}

@(private)
dock_ensure_root :: proc(ctx: ^Context, sp: ^Dock_Space) -> ^Dock_Node {
	if sp.root == nil {
		sp.root = dock_new_node(ctx, sp, .Tabs)
	}
	return sp.root
}

@(private)
dock_add_tab :: proc(ctx: ^Context, n: ^Dock_Node, tab: Dock_Tab, focus := true) -> int {
	append(&n.tabs, tab)
	idx := len(n.tabs) - 1
	if focus || idx == 0 {
		n.active = idx
	}
	mark_dirty(ctx)
	return idx
}

@(private)
dock_take_tab :: proc(ctx: ^Context, n: ^Dock_Node, idx: int) -> Dock_Tab {
	tab := n.tabs[idx]
	ordered_remove(&n.tabs, idx)
	if n.active >= len(n.tabs) {
		n.active = max(len(n.tabs) - 1, 0)
	}
	mark_dirty(ctx)
	return tab
}

@(private)
dock_close_tab :: proc(ctx: ^Context, sp: ^Dock_Space, n: ^Dock_Node, idx: int) {
	tab := dock_take_tab(ctx, n, idx)
	if tab.open != nil {
		tab.open^ = false
	}
	delete(tab.title, ctx.allocator)
	dock_collapse(ctx, sp, n)
}

@(private)
dock_queue_close :: proc(ctx: ^Context, sp: ^Dock_Space, n: ^Dock_Node, title: string) {
	for a in ctx.dock_actions {
		if a.space == sp && a.title == title {
			return
		}
	}
	append(&ctx.dock_actions, Dock_Action{kind = .Close, space = sp, node = n, title = title})
}

@(private)
dock_node_alive :: proc(ctx: ^Context, n: ^Dock_Node) -> bool {
	if n == nil {
		return false
	}
	found, ok := ctx.dock_nodes[n.id]
	return ok && found == n
}

@(private)
dock_apply_actions :: proc(ctx: ^Context) {
	if len(ctx.dock_actions) == 0 {
		return
	}
	for a in ctx.dock_actions {
		if a.kind != .Close || !dock_node_alive(ctx, a.node) {
			continue
		}
		n, idx := dock_find_tab(a.space, a.title)
		if n == nil {
			continue
		}
		dock_close_tab(ctx, a.space, n, idx)
	}
	clear(&ctx.dock_actions)
}

@(private)
dock_collapse :: proc(ctx: ^Context, sp: ^Dock_Space, n: ^Dock_Node) {
	if n == nil || n.kind != .Tabs || len(n.tabs) > 0 {
		return
	}
	if n.viewport != nil {
		viewport_release(ctx, n.viewport)
		return
	}
	p := n.parent
	if p == nil {
		return
	}

	sib := p.children[0] == n ? p.children[1] : p.children[0]
	gp := p.parent
	sib.parent = gp
	if gp == nil {
		sp.root = sib
	} else if gp.children[0] == p {
		gp.children[0] = sib
	} else {
		gp.children[1] = sib
	}

	dock_free_node(ctx, n)
	dock_free_node(ctx, p)
	mark_dirty(ctx)
}

@(private)
dock_split_node :: proc(
	ctx: ^Context,
	sp: ^Dock_Space,
	target: ^Dock_Node,
	side: Dock_Side,
	ratio: f32,
) -> (
	first, second: ^Dock_Node,
) {
	if target == nil {
		return nil, nil
	}

	split := dock_new_node(ctx, sp, .Split)
	fresh := dock_new_node(ctx, sp, .Tabs)
	split.dir = side == .Left || side == .Right ? .Row : .Column
	r := clamp(ratio <= 0 ? 0.5 : ratio, 0.05, 0.95)

	if side == .Left || side == .Top {
		split.children[0] = fresh
		split.children[1] = target
		split.ratio = r
	} else {
		split.children[0] = target
		split.children[1] = fresh
		split.ratio = 1 - r
	}

	p := target.parent
	split.parent = p
	if p == nil {
		sp.root = split
	} else if p.children[0] == target {
		p.children[0] = split
	} else {
		p.children[1] = split
	}

	target.parent = split
	fresh.parent = split
	split.rect = target.rect
	dock_place(sp, split, split.rect)

	return split.children[0], split.children[1]
}

@(private)
dock_find_tab :: proc(sp: ^Dock_Space, title: string) -> (^Dock_Node, int) {
	if n, i := dock_find_in(sp.root, title); n != nil {
		return n, i
	}
	for d in sp.detached {
		if n, i := dock_find_in(d, title); n != nil {
			return n, i
		}
	}
	return nil, -1
}

@(private)
dock_find_anywhere :: proc(
	ctx: ^Context,
	sp: ^Dock_Space,
	title: string,
) -> (
	^Dock_Node,
	int,
) {
	if n, i := dock_find_tab(sp, title); n != nil {
		return n, i
	}
	for _, other in ctx.docks {
		if other == sp {
			continue
		}
		if n, i := dock_find_tab(other, title); n != nil {
			return n, i
		}
	}
	return nil, -1
}

@(private)
dock_find_in :: proc(n: ^Dock_Node, title: string) -> (^Dock_Node, int) {
	if n == nil {
		return nil, -1
	}
	if n.kind == .Tabs {
		for tab, i in n.tabs {
			if tab.title == title {
				return n, i
			}
		}
		return nil, -1
	}
	for c in n.children {
		if f, i := dock_find_in(c, title); f != nil {
			return f, i
		}
	}
	return nil, -1
}

@(private)
dock_insert_default :: proc(
	ctx: ^Context,
	sp: ^Dock_Space,
	title: string,
) -> (
	^Dock_Node,
	int,
) {
	dest := dock_largest_tabs(sp.root)
	if dest == nil {
		dest = dock_ensure_root(ctx, sp)
	}
	if dest.kind != .Tabs {
		return nil, -1
	}
	idx := dock_add_tab(ctx, dest, Dock_Tab{title = strings.clone(title, ctx.allocator)}, false)
	return dest, idx
}

@(private)
dock_largest_tabs :: proc(n: ^Dock_Node) -> ^Dock_Node {
	if n == nil {
		return nil
	}
	if n.kind == .Tabs {
		return n
	}
	a := dock_largest_tabs(n.children[0])
	b := dock_largest_tabs(n.children[1])
	if a == nil {
		return b
	}
	if b == nil {
		return a
	}
	return a.rect.w * a.rect.h >= b.rect.w * b.rect.h ? a : b
}

@(private)
dock_content_rect :: proc(n: ^Node) -> Rect {
	if n == nil {
		return {}
	}
	e := inner_edges(&n.computed)
	return {
		n.rect.x + e.l,
		n.rect.y + e.t,
		max(n.rect.w - e.l - e.r, 0),
		max(n.rect.h - e.t - e.b, 0),
	}
}

@(private)
dock_resolve :: proc(ctx: ^Context, sp: ^Dock_Space) {
	sp.rect = dock_content_rect(sp.node)
	dock_place(sp, sp.root, sp.rect)
	for d in sp.detached {
		r := Rect{}
		if d.viewport != nil {
			r = {0, 0, d.viewport.rect.w, d.viewport.rect.h}
		}
		dock_place(sp, d, r)
	}
}

@(private)
dock_place :: proc(sp: ^Dock_Space, n: ^Dock_Node, r: Rect) {
	if n == nil {
		return
	}
	n.rect = r
	if n.kind != .Split {
		return
	}

	s := sp.cfg.splitter
	if n.dir == .Row {
		avail := max(r.w - s, 0)
		a := clamp(avail * n.ratio, 0, avail)
		dock_place(sp, n.children[0], {r.x, r.y, a, r.h})
		dock_place(sp, n.children[1], {r.x + a + s, r.y, avail - a, r.h})
	} else {
		avail := max(r.h - s, 0)
		a := clamp(avail * n.ratio, 0, avail)
		dock_place(sp, n.children[0], {r.x, r.y, r.w, a})
		dock_place(sp, n.children[1], {r.x, r.y + a + s, r.w, avail - a})
	}
}

@(private)
dock_body_rect :: proc(sp: ^Dock_Space, n: ^Dock_Node) -> Rect {
	h := min(sp.cfg.tab_height, n.rect.h)
	return {n.rect.x, n.rect.y + h, n.rect.w, max(n.rect.h - h, 0)}
}

@(private)
dock_tab_visible :: proc(ctx: ^Context, tab: Dock_Tab) -> bool {
	return tab.seen != 0 && tab.seen + 1 >= ctx.frame_index
}

@(private)
dock_fix_active :: proc(ctx: ^Context, sp: ^Dock_Space) {
	dock_walk(sp.root, ctx, dock_fix_active_node)
	for d in sp.detached {
		dock_fix_active_node(d, ctx)
	}
}

@(private)
dock_fix_active_node :: proc(n: ^Dock_Node, ctx: ^Context) {
	if n.kind != .Tabs || len(n.tabs) == 0 {
		return
	}
	n.active = clamp(n.active, 0, len(n.tabs) - 1)
	if dock_tab_visible(ctx, n.tabs[n.active]) {
		return
	}
	for tab, i in n.tabs {
		if dock_tab_visible(ctx, tab) {
			n.active = i
			return
		}
	}
}

@(private)
dock_walk :: proc(n: ^Dock_Node, ctx: ^Context, fn: proc(n: ^Dock_Node, ctx: ^Context)) {
	if n == nil {
		return
	}
	fn(n, ctx)
	if n.kind == .Split {
		dock_walk(n.children[0], ctx, fn)
		dock_walk(n.children[1], ctx, fn)
	}
}

@(private)
dock_chrome :: proc(ctx: ^Context, sp: ^Dock_Space, loc: runtime.Source_Code_Location) {
	dock_chrome_node(ctx, sp, sp.root, loc)
	for d in sp.detached {
		dock_chrome_node(ctx, sp, d, loc)
	}
}

@(private)
dock_chrome_node :: proc(
	ctx: ^Context,
	sp: ^Dock_Space,
	n: ^Dock_Node,
	loc: runtime.Source_Code_Location,
) {
	if n == nil {
		return
	}
	if n.kind == .Tabs {
		dock_tab_bar(ctx, sp, n, loc)
		return
	}
	dock_splitter(ctx, sp, n, loc)
	dock_chrome_node(ctx, sp, n.children[0], loc)
	dock_chrome_node(ctx, sp, n.children[1], loc)
}

@(private)
dock_fixed :: proc(key: string, r: Rect) -> Element {
	return Element {
		key = key,
		props = {position = .Fixed, inset = {l = r.x, t = r.y}, w = Px(r.w), h = Px(r.h)},
	}
}

@(private)
dock_tab_bar :: proc(
	ctx: ^Context,
	sp: ^Dock_Space,
	n: ^Dock_Node,
	loc: runtime.Source_Code_Location,
) {
	if n.rect.w <= 0 || n.rect.h <= 0 {
		return
	}
	h := min(sp.cfg.tab_height, n.rect.h)
	if h <= 0 {
		return
	}

	t := &ctx.theme
	push_id_int(i64(n.id))
	defer pop_id(loc)

	bar := dock_fixed(DOCK_BAR_KEY, {n.rect.x, n.rect.y, n.rect.w, h})
	bar.flags = {.Clip, .Scroll_X}
	bar.props.dir = .Row
	bar.props.gap = {DOCK_TAB_GAP, 0}
	bar.props.bg = t.raised
	bar.props.z = 1

	bit := begin(bar, loc)
	bit.node.viewport = n.viewport

	for i := 0; i < len(n.tabs); i += 1 {
		if dock_tab_visible(ctx, n.tabs[i]) {
			dock_tab(ctx, sp, n, i, loc)
		}
	}
	end()
}

@(private)
dock_tab :: proc(
	ctx: ^Context,
	sp: ^Dock_Space,
	n: ^Dock_Node,
	idx: int,
	loc: runtime.Source_Code_Location,
) {
	t := &ctx.theme
	tab := n.tabs[idx]
	on := idx == n.active

	e := Element {
		key = tab.title,
		flags = {.Clickable, .Draggable},
		props = {
			w = FIT,
			h = STRETCH,
			dir = .Row,
			align = .Center,
			gap = {6, 0},
			pad = DOCK_TAB_PAD,
			bg = t.surface,
			color = t.text_muted,
			radius = rad4(DOCK_RADIUS, DOCK_RADIUS, 0, 0),
			cursor = .Pointer,
		},
		hover = {bg = t.overlay},
		rules = rule_one(ctx, {.Checked}, {bg = t.bg, color = t.text}),
		state = on ? {.Checked} : {},
	}

	it := begin(e, loc)
	leaf({key = "lbl", text = tab.title, props = {w = FIT, h = FIT}}, loc)

	closed := false
	if tab.open != nil {
		ci := leaf(
			{
				key = "close",
				text = "x",
				flags = {.Clickable},
				props = {
					w = Px(DOCK_CLOSE_W),
					h = Px(DOCK_CLOSE_W),
					justify = .Center,
					align = .Center,
					color = t.text_faint,
					radius = rad(2),
				},
				hover = {bg = t.danger, color = t.accent_text},
			},
			loc,
		)
		if ci.clicked {
			closed = true
		}
	}
	end()

	if it.middle_clicked && tab.open != nil {
		closed = true
	}
	if closed {
		dock_queue_close(ctx, sp, n, tab.title)
		return
	}

	if it.dragging {
		dock_drag_begin(ctx, sp, n, idx)
	} else if it.clicked && !ctx.dock_drag.active {
		n.active = idx
		mark_dirty(ctx)
	}
}

@(private)
dock_split_rect :: proc(sp: ^Dock_Space, n: ^Dock_Node) -> Rect {
	a := n.children[0].rect
	s := sp.cfg.splitter
	if n.dir == .Row {
		return {a.x + a.w, n.rect.y, s, n.rect.h}
	}
	return {n.rect.x, a.y + a.h, n.rect.w, s}
}

@(private)
Dock_Grab :: struct {
	ratio: f32,
}

@(private)
dock_splitter :: proc(
	ctx: ^Context,
	sp: ^Dock_Space,
	n: ^Dock_Node,
	loc: runtime.Source_Code_Location,
) {
	r := dock_split_rect(sp, n)
	if r.w <= 0 || r.h <= 0 {
		return
	}

	t := &ctx.theme
	push_id_int(i64(n.id))
	defer pop_id(loc)

	e := dock_fixed(DOCK_SPLIT_KEY, r)
	e.flags = {.Draggable}
	e.props.bg = t.divider
	e.props.cursor = n.dir == .Row ? .Resize_H : .Resize_V
	e.props.z = 2
	e.hover = {bg = t.accent}

	it := leaf(e, loc)
	it.node.viewport = n.viewport

	g := state_of(it.node, Dock_Grab)
	// @Note: The element has `.Draggable`, thus `press_left` holds the pointer
	// with an implicit capture, and that capture goes away on mouse up. A call
	// of `capture_mouse` here makes the capture explicit. `step_mouse` then
	// keeps it after the release, and no hit test runs again.
	if it.pressed {
		g.ratio = n.ratio
	}
	if !it.dragging {
		return
	}

	avail := n.dir == .Row ? max(n.rect.w - sp.cfg.splitter, 0) : max(n.rect.h - sp.cfg.splitter, 0)
	if avail <= 0 {
		return
	}
	moved := ctx.input.mouse.y - it.drag_start.y
	if n.dir == .Row {
		moved = ctx.input.mouse.x - it.drag_start.x
	}

	lo := n.dir == .Row ? sp.cfg.min_panel.x : sp.cfg.min_panel.y
	lo = clamp(lo / avail, 0, 1)
	hi := clamp(1 - lo, 0, 1)
	if lo > hi {
		lo, hi = 0.5, 0.5
	}

	next := clamp(g.ratio + moved / avail, lo, hi)
	if next != n.ratio {
		n.ratio = next
		mark_dirty(ctx)
	}
	request_frame(loc)
}

@(private)
dock_drag_reset :: proc(ctx: ^Context) {
	d := &ctx.dock_drag
	if d.frame == ctx.frame_index {
		return
	}
	d.frame = ctx.frame_index
	d.space = nil
	d.target = nil
	d.zone = .None
	d.outer = false
	d.rect = {}
	if d.active && .Left not_in ctx.input.mouse_down && .Left not_in ctx.input.mouse_released {
		d.active = false
	}
}

@(private)
dock_drag_begin :: proc(ctx: ^Context, sp: ^Dock_Space, n: ^Dock_Node, idx: int) {
	d := &ctx.dock_drag
	if d.active {
		return
	}
	d.active = true
	d.origin = sp
	d.from = n
	d.title = n.tabs[idx].title
}

@(private)
dock_pointer_desktop :: proc(ctx: ^Context) -> Vec2 {
	if v := ctx.pointer_viewport; v != nil {
		return ctx.input.mouse + {v.rect.x, v.rect.y}
	}
	return ctx.input.mouse + ctx.input.window_pos
}

@(private)
dock_desktop_rect :: proc(ctx: ^Context, n: ^Dock_Node) -> Rect {
	o := ctx.input.window_pos
	if v := n.viewport; v != nil {
		o = {v.rect.x, v.rect.y}
	}
	return {n.rect.x + o.x, n.rect.y + o.y, n.rect.w, n.rect.h}
}

@(private)
dock_space_desktop_rect :: proc(ctx: ^Context, sp: ^Dock_Space) -> Rect {
	o := ctx.input.window_pos
	return {sp.rect.x + o.x, sp.rect.y + o.y, sp.rect.w, sp.rect.h}
}

@(private)
dock_zone_of :: proc(r: Rect, p: Vec2) -> Dock_Zone {
	if r.w <= 0 || r.h <= 0 || !rect_contains(r, p) {
		return .None
	}
	fx := (p.x - r.x) / r.w
	fy := (p.y - r.y) / r.h
	l, rr, tp, bt := fx, 1 - fx, fy, 1 - fy
	m := min(min(l, rr), min(tp, bt))
	if m > DOCK_EDGE_FRAC {
		return .Center
	}
	switch m {
	case l:
		return .Left
	case rr:
		return .Right
	case tp:
		return .Top
	}
	return .Bottom
}

@(private)
dock_outer_zone :: proc(r: Rect, p: Vec2) -> Dock_Zone {
	if r.w <= 0 || r.h <= 0 || !rect_contains(r, p) {
		return .None
	}
	band := min(DOCK_OUTER_BAND, min(r.w, r.h) * 0.25)
	if p.x - r.x <= band {
		return .Left
	}
	if r.x + r.w - p.x <= band {
		return .Right
	}
	if p.y - r.y <= band {
		return .Top
	}
	if r.y + r.h - p.y <= band {
		return .Bottom
	}
	return .None
}

@(private)
dock_zone_rect :: proc(base: Rect, zone: Dock_Zone) -> Rect {
	switch zone {
	case .None:
		return {}
	case .Center:
		return base
	case .Left:
		return {base.x, base.y, base.w * 0.5, base.h}
	case .Right:
		return {base.x + base.w * 0.5, base.y, base.w * 0.5, base.h}
	case .Top:
		return {base.x, base.y, base.w, base.h * 0.5}
	case .Bottom:
		return {base.x, base.y + base.h * 0.5, base.w, base.h * 0.5}
	}
	return {}
}

@(private)
dock_zone_scan :: proc(ctx: ^Context, sp: ^Dock_Space) {
	d := &ctx.dock_drag
	if !d.active {
		return
	}
	request_frame()

	p := dock_pointer_desktop(ctx)

	outer := dock_space_desktop_rect(ctx, sp)
	if z := dock_outer_zone(outer, p); z != .None && sp.root != nil {
		d.space = sp
		d.target = sp.root
		d.zone = z
		d.outer = true
		d.rect = dock_zone_rect(outer, z)
		return
	}

	hit := dock_hit_tabs(ctx, sp.root, p)
	if hit == nil {
		for det in sp.detached {
			if h := dock_hit_tabs(ctx, det, p); h != nil {
				hit = h
				break
			}
		}
	}
	if hit == nil {
		return
	}

	r := dock_desktop_rect(ctx, hit)
	z := dock_zone_of(r, p)
	if z == .None {
		return
	}
	d.space = sp
	d.target = hit
	d.zone = z
	d.outer = false
	d.rect = dock_zone_rect(r, z)
}

@(private)
dock_hit_tabs :: proc(ctx: ^Context, n: ^Dock_Node, p: Vec2) -> ^Dock_Node {
	if n == nil {
		return nil
	}
	if n.kind == .Tabs {
		return rect_contains(dock_desktop_rect(ctx, n), p) ? n : nil
	}
	if h := dock_hit_tabs(ctx, n.children[0], p); h != nil {
		return h
	}
	return dock_hit_tabs(ctx, n.children[1], p)
}

@(private)
dock_local_rect :: proc(ctx: ^Context, r: Rect, v: ^Viewport) -> Rect {
	o := ctx.input.window_pos
	if v != nil {
		o = {v.rect.x, v.rect.y}
	}
	return {r.x - o.x, r.y - o.y, r.w, r.h}
}

@(private)
dock_overlay :: proc(ctx: ^Context, sp: ^Dock_Space, loc: runtime.Source_Code_Location) {
	d := &ctx.dock_drag
	if !d.active {
		return
	}
	t := &ctx.theme

	if d.space == sp && d.zone != .None {
		v := d.target != nil ? d.target.viewport : nil
		r := dock_local_rect(ctx, d.rect, v)
		e := dock_fixed(DOCK_DROP_KEY, r)
		e.flags = {.Floating, .Pass_Through, .No_Anim}
		e.props.z = 40
		e.props.bg = fade(t.accent, 0.35)
		e.props.border = {width = all(2), color = t.accent}
		e.props.radius = rad(DOCK_RADIUS)
		it := leaf(e, loc)
		it.node.viewport = v
	}

	if d.origin == sp {
		v := ctx.pointer_viewport
		p := ctx.input.mouse
		e := Element {
			key = DOCK_GHOST_KEY,
			text = d.title,
			flags = {.Floating, .Pass_Through, .No_Anim},
			props = {
				position = .Fixed,
				inset = {l = p.x + 8, t = p.y + 8},
				w = FIT,
				h = FIT,
				pad = DOCK_TAB_PAD,
				bg = t.overlay,
				color = t.text,
				radius = rad(DOCK_RADIUS),
				border = {width = all(1), color = t.accent},
				z = 41,
			},
		}
		it := leaf(e, loc)
		it.node.viewport = v
	}
}

@(private)
settle_docks :: proc(ctx: ^Context) {
	dock_apply_actions(ctx)

	d := &ctx.dock_drag
	if !d.active {
		return
	}
	if .Left in ctx.input.mouse_down {
		return
	}
	d.active = false

	if !dock_node_alive(ctx, d.from) || d.title == "" {
		return
	}
	if d.target != nil && !dock_node_alive(ctx, d.target) {
		return
	}
	idx := -1
	for tab, i in d.from.tabs {
		if tab.title == d.title {
			idx = i
			break
		}
	}
	if idx < 0 {
		return
	}

	if d.zone == .None {
		dock_drop_outside(ctx, d, idx)
		return
	}
	dock_drop_zone(ctx, d, idx)
}

@(private)
dock_drop_outside :: proc(ctx: ^Context, d: ^Dock_Drag, idx: int) {
	sp := d.origin
	if sp == nil || sp.cfg.mode != .Detachable {
		return
	}
	if d.from.viewport != nil && len(d.from.tabs) == 1 {
		return
	}
	dock_detach_tab(ctx, sp, d.from, idx, dock_pointer_desktop(ctx))
}

@(private)
dock_drop_zone :: proc(ctx: ^Context, d: ^Dock_Drag, idx: int) {
	sp := d.space
	target := d.target
	if sp == nil || target == nil {
		return
	}
	if d.from == target && len(d.from.tabs) == 1 {
		return
	}

	src := d.from
	if d.zone == .Center {
		if src == target {
			return
		}
		tab := dock_take_tab(ctx, src, idx)
		dock_add_tab(ctx, target, tab)
		dock_collapse(ctx, src.space, src)
		return
	}

	side: Dock_Side
	switch d.zone {
	case .Left:
		side = .Left
	case .Right:
		side = .Right
	case .Top:
		side = .Top
	case .Bottom:
		side = .Bottom
	case .Center, .None:
		return
	}

	tab := dock_take_tab(ctx, src, idx)
	first, second := dock_split_node(ctx, sp, target, side, 0.5)
	fresh := side == .Left || side == .Top ? first : second
	dock_add_tab(ctx, fresh, tab)
	dock_collapse(ctx, src.space, src)
}

@(private)
free_docks :: proc(ctx: ^Context) {
	for _, sp in ctx.docks {
		dock_free_tree(ctx, sp.root)
		for d in sp.detached {
			dock_free_tree(ctx, d)
		}
		delete(sp.detached)
		for key, value in sp.pending {
			delete(key, ctx.allocator)
			delete(value, ctx.allocator)
		}
		delete(sp.pending)
		delete(sp.id, ctx.allocator)
		free(sp, ctx.allocator)
	}
	delete(ctx.docks)
	ctx.docks = {}
	delete(ctx.dock_order)
	ctx.dock_order = {}
	delete(ctx.dock_nodes)
	ctx.dock_nodes = {}
	delete(ctx.dock_actions)
	ctx.dock_actions = {}
	ctx.dock_drag = {}
}

@(private)
dock_free_tree :: proc(ctx: ^Context, n: ^Dock_Node) {
	if n == nil {
		return
	}
	if n.kind == .Split {
		dock_free_tree(ctx, n.children[0])
		dock_free_tree(ctx, n.children[1])
	}
	dock_free_node(ctx, n)
}

@(private)
dock_register_handler :: proc(ctx: ^Context) {
	if ctx.dock_handler {
		return
	}
	ctx.dock_handler = true
	settings_handler_ctx(
		ctx,
		{
			section = DOCK_SECTION,
			user = ctx,
			read = proc(name, key, value: string, user: rawptr) {
				c := (^Context)(user)
				if name == "" {
					return
				}
				sp := dock_space_get(c, name)
				dock_pending_set(c, sp, key, value)
			},
			write = proc(w: Writer, user: rawptr) {
				dock_write_all((^Context)(user), w)
			},
		},
	)
}

@(private)
dock_pending_set :: proc(ctx: ^Context, sp: ^Dock_Space, key, value: string) {
	if old, ok := sp.pending[key]; ok {
		delete(old, ctx.allocator)
		sp.pending[key] = strings.clone(value, ctx.allocator)
		return
	}
	sp.pending[strings.clone(key, ctx.allocator)] = strings.clone(value, ctx.allocator)
}

@(private)
dock_apply_pending :: proc(ctx: ^Context, sp: ^Dock_Space) {
	if len(sp.pending) == 0 {
		return
	}
	dock_rebuild(ctx, sp)
	for key, value in sp.pending {
		delete(key, ctx.allocator)
		delete(value, ctx.allocator)
	}
	clear(&sp.pending)
}

dock_save :: proc(dock: Dock_Id, w: Writer) {
	ctx := ctx_of()
	sp := dock_space_by_handle(ctx, dock)
	if sp == nil {
		return
	}
	dock_write_space(ctx, w, sp)
}

dock_load :: proc(dock: Dock_Id, data: []byte) -> bool {
	ctx := ctx_of()
	sp := dock_space_by_handle(ctx, dock)
	if sp == nil {
		return false
	}
	for e in ini_entries(string(data), ctx.frame_allocator) {
		if e.section != DOCK_SECTION {
			continue
		}
		if e.name != "" && e.name != sp.id {
			continue
		}
		dock_pending_set(ctx, sp, e.key, e.value)
	}
	if len(sp.pending) == 0 {
		return false
	}
	dock_apply_pending(ctx, sp)
	return true
}

@(private)
dock_write_all :: proc(ctx: ^Context, w: Writer) {
	names := sorted_keys(ctx, ctx.docks)
	for i in 0 ..< len(names) {
		if i > 0 {
			blank(w)
		}
		dock_write_space(ctx, w, ctx.docks[names[i]])
	}
}

@(private)
dock_write_space :: proc(ctx: ^Context, w: Writer, sp: ^Dock_Space) {
	ini.write_section(
		w,
		strings.concatenate({DOCK_SECTION, ".", sp.id}, ctx.frame_allocator),
	)
	if sp.root == nil {
		return
	}

	names := make(map[^Dock_Node]string, 16, ctx.frame_allocator)
	defer delete(names)
	serial := 0
	dock_name_nodes(ctx, sp.root, &names, &serial)
	for d in sp.detached {
		dock_name_nodes(ctx, d, &names, &serial)
	}

	ini.write_pair(w, "root", names[sp.root])
	if len(sp.detached) > 0 {
		parts := make([dynamic]string, 0, len(sp.detached), ctx.frame_allocator)
		for d in sp.detached {
			append(&parts, names[d])
		}
		ini.write_pair(w, "detached", strings.join(parts[:], " ", ctx.frame_allocator))
	}
	dock_write_node(ctx, w, sp.root, names)
	for d in sp.detached {
		dock_write_node(ctx, w, d, names)
	}
}

@(private)
dock_name_nodes :: proc(
	ctx: ^Context,
	n: ^Dock_Node,
	names: ^map[^Dock_Node]string,
	serial: ^int,
) {
	if n == nil {
		return
	}
	names[n] = fmt.aprintf("n%d", serial^, allocator = ctx.frame_allocator)
	serial^ += 1
	if n.kind == .Split {
		dock_name_nodes(ctx, n.children[0], names, serial)
		dock_name_nodes(ctx, n.children[1], names, serial)
	}
}

@(private)
dock_write_node :: proc(ctx: ^Context, w: Writer, n: ^Dock_Node, names: map[^Dock_Node]string) {
	if n == nil {
		return
	}
	id := names[n]
	if n.kind == .Split {
		ini.write_pair(w, dock_key(ctx, id, "kind"), "split")
		ini.write_pair(w, dock_key(ctx, id, "dir"), n.dir == .Row ? "row" : "column")
		ini.write_pair(w, dock_key(ctx, id, "ratio"), f32_string(n.ratio, ctx.frame_allocator))
		ini.write_pair(
			w,
			dock_key(ctx, id, "children"),
			strings.concatenate(
				{names[n.children[0]], " ", names[n.children[1]]},
				ctx.frame_allocator,
			),
		)
		dock_write_node(ctx, w, n.children[0], names)
		dock_write_node(ctx, w, n.children[1], names)
		return
	}

	ini.write_pair(w, dock_key(ctx, id, "kind"), "tabs")
	titles := make([dynamic]string, 0, len(n.tabs), ctx.frame_allocator)
	for tab in n.tabs {
		append(&titles, tab.title)
	}
	ini.write_pair(w, dock_key(ctx, id, "tabs"), strings.join(titles[:], "|", ctx.frame_allocator))
	ini.write_pair(w, dock_key(ctx, id, "active"), fmt.aprintf("%d", n.active, allocator = ctx.frame_allocator))
	if n.viewport != nil {
		ini.write_pair(
			w,
			dock_key(ctx, id, "viewport"),
			fmt.aprintf(
				"%v %v %v %v",
				n.viewport.rect.x,
				n.viewport.rect.y,
				n.viewport.rect.w,
				n.viewport.rect.h,
				allocator = ctx.frame_allocator,
			),
		)
	}
}

@(private)
dock_key :: proc(ctx: ^Context, id, field: string) -> string {
	return strings.concatenate({id, ".", field}, ctx.frame_allocator)
}

@(private)
dock_rebuild :: proc(ctx: ^Context, sp: ^Dock_Space) {
	root_name, ok := sp.pending["root"]
	if !ok {
		return
	}

	dock_free_tree(ctx, sp.root)
	sp.root = nil
	for d in sp.detached {
		if d.viewport != nil {
			viewport_drop(ctx, d.viewport)
		}
		dock_free_tree(ctx, d)
	}
	clear(&sp.detached)

	sp.root = dock_read_node(ctx, sp, root_name, nil)
	if sp.root == nil {
		sp.root = dock_new_node(ctx, sp, .Tabs)
		return
	}

	if list, has := sp.pending["detached"]; has {
		for name in strings.split(strings.trim_space(list), " ", ctx.frame_allocator) {
			if name == "" {
				continue
			}
			d := dock_read_node(ctx, sp, name, nil)
			if d == nil {
				continue
			}
			if d.viewport == nil {
				dock_absorb(ctx, sp, d)
				continue
			}
			append(&sp.detached, d)
		}
	}
}

@(private)
dock_absorb :: proc(ctx: ^Context, sp: ^Dock_Space, n: ^Dock_Node) {
	dest := dock_largest_tabs(sp.root)
	if dest == nil {
		dest = dock_ensure_root(ctx, sp)
	}
	for tab in n.tabs {
		append(&dest.tabs, tab)
	}
	clear(&n.tabs)
	dest.active = clamp(dest.active, 0, max(len(dest.tabs) - 1, 0))
	dock_free_node(ctx, n)
}

@(private)
dock_read_node :: proc(
	ctx: ^Context,
	sp: ^Dock_Space,
	name: string,
	parent: ^Dock_Node,
) -> ^Dock_Node {
	kind, ok := sp.pending[dock_key(ctx, name, "kind")]
	if !ok {
		return nil
	}

	if kind == "split" {
		kids, has := sp.pending[dock_key(ctx, name, "children")]
		if !has {
			return nil
		}
		parts := strings.split(strings.trim_space(kids), " ", ctx.frame_allocator)
		if len(parts) != 2 {
			return nil
		}

		n := dock_new_node(ctx, sp, .Split)
		n.parent = parent
		n.dir = sp.pending[dock_key(ctx, name, "dir")] == "column" ? .Column : .Row
		if r, rok := parse_f32(sp.pending[dock_key(ctx, name, "ratio")]); rok {
			n.ratio = clamp(r, 0.05, 0.95)
		}
		n.children[0] = dock_read_node(ctx, sp, parts[0], n)
		n.children[1] = dock_read_node(ctx, sp, parts[1], n)
		if n.children[0] == nil || n.children[1] == nil {
			dock_free_tree(ctx, n.children[0])
			dock_free_tree(ctx, n.children[1])
			dock_free_node(ctx, n)
			return nil
		}
		return n
	}

	n := dock_new_node(ctx, sp, .Tabs)
	n.parent = parent
	if titles, has := sp.pending[dock_key(ctx, name, "tabs")]; has {
		for title in strings.split(titles, "|", ctx.frame_allocator) {
			if title == "" {
				continue
			}
			append(&n.tabs, Dock_Tab{title = strings.clone(title, ctx.allocator)})
		}
	}
	if a, has := sp.pending[dock_key(ctx, name, "active")]; has {
		if v, vok := strconv.parse_int(strings.trim_space(a)); vok {
			n.active = clamp(v, 0, max(len(n.tabs) - 1, 0))
		}
	}
	if r, has := sp.pending[dock_key(ctx, name, "viewport")]; has {
		dock_restore_viewport(ctx, sp, n, r)
	}
	return n
}

@(private)
dock_rect_of :: proc(s: string) -> (Rect, bool) {
	fields := strings.fields(strings.trim_space(s), context.temp_allocator)
	defer delete(fields, context.temp_allocator)
	if len(fields) != 4 {
		return {}, false
	}
	out: [4]f32
	for f, i in fields {
		v, ok := strconv.parse_f32(f)
		if !ok {
			return {}, false
		}
		out[i] = v
	}
	return {out[0], out[1], out[2], out[3]}, true
}

