package loom

import "base:runtime"
import "core:fmt"

Flag :: enum u16 {
	Clickable,
	Focusable,
	Draggable,
	Scroll_X,
	Scroll_Y,
	Clip,
	Group,
	Floating,
	Pass_Through,
	Disabled,
	No_Anim,
}

Flags :: bit_set[Flag;u16]

Element :: struct {
	key:         string,
	flags:       Flags,
	text:        string,
	using props: Props,
	hover:       Props,
	active:      Props,
	focus:       Props,
	disabled:    Props,
	group_hover: Props,
	rules:       []Rule,
	transition:  Transition,
	state:       State_Set,
}

Node :: struct {
	id:                        Id,
	parent, first_child, next: ^Node,
	rect:                      Rect,
	content:                   Vec2,
	scroll:                    Vec2,
	computed:                  Props,
	state:                     State_Set,
	input_state:               State_Set,
	flags:                     Flags,
	last_touched:              u64,
	user:                      rawptr,
	el:                        Element,
	states:                    ^State_Block,
	draw:                      proc(node: ^Node, user: rawptr),
	draw_user:                 rawptr,
	first_frame:               bool,
	lay:                       ^Layout,
}

begin :: proc(el: Element, loc := #caller_location) -> Interaction {
	ctx := ctx_of(loc)
	assert(ctx.in_frame, "loom: begin called outside a frame", loc)

	id := el.key != "" ? hash_string(ctx.id_seed, el.key) : hash_loc(ctx.id_seed, loc)
	n := touch(ctx, id, loc)
	attach(ctx, n)

	n.el = el
	n.flags = el.flags
	n.state += el.state
	n.draw = nil
	n.draw_user = nil

	append(&ctx.open, Open_Entry{node = n, prev_seed = ctx.id_seed, id_depth = len(ctx.id_stack)})
	ctx.id_seed = n.id

	return interaction(n)
}

end :: proc() {
	ctx := ctx_of()
	assert(ctx.in_frame, "loom: end called outside a frame")
	assert(len(ctx.open) > 1, "loom: end without a matching begin")

	e := pop(&ctx.open)
	if len(ctx.id_stack) != e.id_depth {
		panic(
			fmt.tprintf(
				"loom: push_id/pop_id imbalance inside node id %v key %q, %v entries left over",
				e.node.id,
				e.node.el.key,
				len(ctx.id_stack) - e.id_depth,
			),
		)
	}
	ctx.id_seed = e.prev_seed
}

leaf :: proc(el: Element, loc := #caller_location) -> Interaction {
	it := begin(el, loc)
	end()
	return it
}

@(deferred_none = end)
scope :: proc(el: Element, loc := #caller_location) -> Interaction {
	return begin(el, loc)
}

custom :: proc(
	el: Element,
	draw: proc(node: ^Node, user: rawptr),
	user: rawptr = nil,
	loc := #caller_location,
) -> Interaction {
	it := begin(el, loc)
	n := it.node
	n.draw = draw
	n.draw_user = user
	end()
	return it
}

current :: proc() -> ^Node {
	ctx := ctx_of()
	if len(ctx.open) == 0 {
		return nil
	}
	return ctx.open[len(ctx.open) - 1].node
}

find :: proc(id: Id) -> ^Node {
	ctx := ctx_of()
	n, ok := ctx.nodes[id]
	return n if ok else nil
}

root :: proc() -> ^Node {
	return ctx_of().root
}

@(private)
touch :: proc(ctx: ^Context, id: Id, loc: runtime.Source_Code_Location) -> ^Node {
	n, ok := ctx.nodes[id]
	if !ok {
		n = claim_node(ctx)
		n.id = id
		n.first_frame = true
		ctx.nodes[id] = n
		ctx.live_nodes += 1
	} else {
		n.first_frame = false
	}

	when ODIN_DEBUG {
		if prev, dup := ctx.seen[id]; dup {
			panic(
				fmt.tprintf(
					"loom: duplicate id %v this frame, first at %v(%v:%v), again at %v(%v:%v), pass a stable Element.key",
					id,
					prev.file_path,
					prev.line,
					prev.column,
					loc.file_path,
					loc.line,
					loc.column,
				),
				loc,
			)
		}
		ctx.seen[id] = loc
	}

	n.last_touched = ctx.frame_index
	n.state = n.input_state + (n.state & CARRIED_STATES)
	n.first_child = nil
	n.next = nil
	n.lay = nil
	return n
}

@(private)
attach :: proc(ctx: ^Context, n: ^Node) {
	e := &ctx.open[len(ctx.open) - 1]
	n.parent = e.node
	if e.last_child == nil {
		e.node.first_child = n
	} else {
		e.last_child.next = n
	}
	e.last_child = n
}

@(private)
claim_node :: proc(ctx: ^Context) -> ^Node {
	if ctx.free_nodes != nil {
		n := ctx.free_nodes
		ctx.free_nodes = n.next
		ctx.free_count -= 1
		n^ = {}
		return n
	}
	n, err := new(Node, ctx.allocator)
	assert(err == nil, "loom: out of memory allocating a node")
	return n
}

@(private)
release_node :: proc(ctx: ^Context, n: ^Node) {
	n^ = {}
	n.next = ctx.free_nodes
	ctx.free_nodes = n
	ctx.free_count += 1
	ctx.live_nodes -= 1
}

@(private)
interaction :: proc(n: ^Node) -> Interaction {
	return Interaction{id = n.id, node = n, rect = n.rect, state = n.state}
}
