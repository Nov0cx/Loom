package loom

import "base:runtime"
import "core:mem"

State_Dtor :: proc(data: rawptr, allocator: runtime.Allocator)

State_Block :: struct {
	next:   ^State_Block,
	type:   typeid,
	offset: int,
	size:   int,
	dtor:   State_Dtor,
}

state :: proc($T: typeid, loc := #caller_location) -> ^T {
	ctx := ctx_of(loc)
	assert(len(ctx.open) > 0, "loom: state called outside a frame", loc)
	n := ctx.open[len(ctx.open) - 1].node
	return (^T)(state_raw(ctx, n, T, size_of(T), align_of(T), nil))
}

state_dtor :: proc($T: typeid, dtor: State_Dtor, loc := #caller_location) -> ^T {
	ctx := ctx_of(loc)
	assert(len(ctx.open) > 0, "loom: state_dtor called outside a frame", loc)
	n := ctx.open[len(ctx.open) - 1].node
	return (^T)(state_raw(ctx, n, T, size_of(T), align_of(T), dtor))
}

state_of :: proc(n: ^Node, $T: typeid, loc := #caller_location) -> ^T {
	ctx := ctx_of(loc)
	return (^T)(state_raw(ctx, n, T, size_of(T), align_of(T), nil))
}

state_of_dtor :: proc(n: ^Node, $T: typeid, dtor: State_Dtor, loc := #caller_location) -> ^T {
	ctx := ctx_of(loc)
	return (^T)(state_raw(ctx, n, T, size_of(T), align_of(T), dtor))
}

@(private)
state_raw :: proc(
	ctx: ^Context,
	n: ^Node,
	type: typeid,
	size, alignment: int,
	dtor: State_Dtor,
) -> rawptr {
	for b := n.states; b != nil; b = b.next {
		if b.type == type {
			return block_data(b)
		}
	}

	offset := mem.align_forward_int(size_of(State_Block), max(alignment, align_of(State_Block)))
	total := offset + max(size, 1)

	raw, err := mem.alloc(total, max(alignment, align_of(State_Block)), ctx.allocator)
	assert(err == nil, "loom: out of memory allocating per-node state")
	mem.zero(raw, total)

	b := (^State_Block)(raw)
	b.next = n.states
	b.type = type
	b.offset = offset
	b.size = total
	b.dtor = dtor
	n.states = b
	ctx.state_blocks += 1
	return block_data(b)
}

@(private)
block_data :: proc(b: ^State_Block) -> rawptr {
	return rawptr(uintptr(b) + uintptr(b.offset))
}

@(private)
free_states :: proc(ctx: ^Context, n: ^Node) {
	for b := n.states; b != nil; {
		next := b.next
		if b.dtor != nil {
			b.dtor(block_data(b), ctx.allocator)
		}
		mem.free_with_size(b, b.size, ctx.allocator)
		ctx.state_blocks -= 1
		b = next
	}
	n.states = nil
}

@(private)
state_find :: proc(n: ^Node, type: typeid) -> rawptr {
	for b := n.states; b != nil; b = b.next {
		if b.type == type {
			return block_data(b)
		}
	}
	return nil
}
