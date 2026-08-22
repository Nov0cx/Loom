package loom

import "core:fmt"
import "core:io"
import "core:strings"

Writer :: io.Writer

Stats :: struct {
	live_nodes:   int,
	free_nodes:   int,
	state_blocks: int,
	frame_index:  u64,
	open_depth:   int,
}

stats :: proc() -> Stats {
	ctx := ctx_of()
	return Stats {
		live_nodes = ctx.live_nodes,
		free_nodes = ctx.free_count,
		state_blocks = ctx.state_blocks,
		frame_index = ctx.frame_index,
		open_depth = len(ctx.open),
	}
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
