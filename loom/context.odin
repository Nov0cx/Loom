package loom

import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:sync"

DEFAULT_PRUNE_AFTER :: 2
DEFAULT_DOUBLE_CLICK :: 0.3
DEFAULT_SCROLL_SPEED :: 40

Open_Entry :: struct {
	node:       ^Node,
	last_child: ^Node,
	prev_seed:  Id,
	id_depth:   int,
}

Context :: struct {
	cfg:              Config,
	allocator:        runtime.Allocator,
	frame_allocator:  runtime.Allocator,
	frame_arena:      virtual.Arena,
	owns_frame_arena: bool,
	nodes:            map[Id]^Node,
	free_nodes:       ^Node,
	root:             ^Node,
	open:             [dynamic]Open_Entry,
	id_stack:         [dynamic]Id,
	id_seed:          Id,
	frame_index:      u64,
	in_frame:         bool,
	input:            Input,
	draw_list:        Draw_List,
	live_nodes:       int,
	free_count:       int,
	state_blocks:     int,
	seen:             map[Id]runtime.Source_Code_Location,
}

init :: proc(ctx: ^Context, cfg: Config, allocator := context.allocator) {
	ctx^ = {}
	ctx.allocator = allocator
	ctx.cfg = cfg

	if ctx.cfg.prune_after == 0 {
		ctx.cfg.prune_after = DEFAULT_PRUNE_AFTER
	}
	if ctx.cfg.double_click == 0 {
		ctx.cfg.double_click = DEFAULT_DOUBLE_CLICK
	}
	if ctx.cfg.scroll_speed == 0 {
		ctx.cfg.scroll_speed = DEFAULT_SCROLL_SPEED
	}

	if cfg.frame_allocator.procedure != nil {
		ctx.frame_allocator = cfg.frame_allocator
	} else {
		err := virtual.arena_init_growing(&ctx.frame_arena)
		assert(err == nil, "loom: could not create the frame arena")
		ctx.frame_allocator = virtual.arena_allocator(&ctx.frame_arena)
		ctx.owns_frame_arena = true
	}

	ctx.nodes = make(map[Id]^Node, 64, allocator)
	ctx.open = make([dynamic]Open_Entry, 0, 32, allocator)
	ctx.id_stack = make([dynamic]Id, 0, 16, allocator)
	ctx.seen = make(map[Id]runtime.Source_Code_Location, 64, allocator)

	globals_acquire(allocator)
	make_current(ctx)
}

destroy :: proc(ctx: ^Context) {
	for _, n in ctx.nodes {
		free_states(ctx, n)
		free(n, ctx.allocator)
	}
	delete(ctx.nodes)

	for n := ctx.free_nodes; n != nil; {
		next := n.next
		free(n, ctx.allocator)
		n = next
	}

	delete(ctx.open)
	delete(ctx.id_stack)
	delete(ctx.seen)

	if ctx.owns_frame_arena {
		virtual.arena_destroy(&ctx.frame_arena)
	}

	if g != nil && g.current[sync.current_thread_id()] == ctx {
		make_current(nil)
	}
	globals_release()
	ctx^ = {}
}

begin_frame :: proc(input: Input) {
	begin_frame_ctx(ctx_of(), input)
}

begin_frame_ctx :: proc(ctx: ^Context, input: Input) {
	assert(!ctx.in_frame, "loom: begin_frame called twice without an end_frame")

	ctx.frame_index += 1
	ctx.in_frame = true
	if ctx.owns_frame_arena {
		virtual.arena_free_all(&ctx.frame_arena)
	}
	ctx.input = input
	ctx.draw_list = {}

	clear(&ctx.open)
	clear(&ctx.id_stack)
	clear(&ctx.seen)
	ctx.id_seed = 0

	recompute_states(ctx)

	el := Element {
		key   = ROOT_KEY,
		props = ctx.cfg.root,
	}
	if el.props.w == nil {
		el.props.w = Px(input.viewport.x)
	}
	if el.props.h == nil {
		el.props.h = Px(input.viewport.y)
	}

	root := touch(ctx, hash_string(0, ROOT_KEY), #location(begin_frame_ctx))
	root.parent = nil
	root.el = el
	root.computed = el.props
	root.rect = {0, 0, input.viewport.x, input.viewport.y}
	ctx.root = root

	append(&ctx.open, Open_Entry{node = root, prev_seed = 0, id_depth = 0})
	ctx.id_seed = root.id
}

end_frame :: proc() -> Draw_List {
	return end_frame_ctx(ctx_of())
}

end_frame_ctx :: proc(ctx: ^Context) -> Draw_List {
	assert(ctx.in_frame, "loom: end_frame without a begin_frame")

	if len(ctx.open) > 1 {
		open := ctx.open[len(ctx.open) - 1].node
		panic(
			fmt.tprintf(
				"loom: %v node(s) still open at end_frame, innermost is id %v key %q",
				len(ctx.open) - 1,
				open.id,
				open.el.key,
			),
		)
	}
	assert(len(ctx.open) == 1, "loom: end_frame lost the root node")
	assert(len(ctx.id_stack) == 0, "loom: push_id without a matching pop_id")

	pop(&ctx.open)
	ctx.id_seed = 0
	ctx.in_frame = false

	prune(ctx)
	return ctx.draw_list
}

@(private)
recompute_states :: proc(ctx: ^Context) {
}

@(private)
prune :: proc(ctx: ^Context) {
	if ctx.frame_index <= u64(ctx.cfg.prune_after) {
		return
	}
	deadline := ctx.frame_index - u64(ctx.cfg.prune_after)

	doomed := make([dynamic]Id, 0, 16, ctx.frame_allocator)
	defer delete(doomed)

	for id, n in ctx.nodes {
		if n.last_touched < deadline {
			append(&doomed, id)
		}
	}

	for id in doomed {
		n := ctx.nodes[id]
		delete_key(&ctx.nodes, id)
		free_states(ctx, n)
		release_node(ctx, n)
	}
}
