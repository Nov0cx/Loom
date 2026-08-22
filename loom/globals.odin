package loom

import "base:runtime"
import "core:fmt"
import "core:sync"

Globals :: struct {
	version:   Version,
	ctx_size:  int,
	node_size: int,
	allocator: runtime.Allocator,
	mutex:     sync.Mutex,
	current:   map[int]^Context,
	contexts:  int,
}

@(private)
g: ^Globals

get_globals :: proc() -> ^Globals {
    assert(g != nil, "globals are not set")
	return g
}

set_globals :: proc(incoming: ^Globals) {
	assert(incoming != nil, "loom: set_globals was given nil")
	assert(
		incoming.version == VERSION,
		fmt.tprintf(
			"loom: version mismatch, this module is %v.%v and the host is %v.%v",
			VERSION.major,
			VERSION.minor,
			incoming.version.major,
			incoming.version.minor,
		),
	)
	assert(
		incoming.ctx_size == size_of(Context),
		fmt.tprintf(
			"loom: Context layout mismatch, this module has %v bytes and the host has %v",
			size_of(Context),
			incoming.ctx_size,
		),
	)
	assert(
		incoming.node_size == size_of(Node),
		fmt.tprintf(
			"loom: Node layout mismatch, this module has %v bytes and the host has %v",
			size_of(Node),
			incoming.node_size,
		),
	)
	g = incoming
}

make_current :: proc(ctx: ^Context) -> ^Context {
	assert(g != nil, "loom: init or set_globals must run before make_current")
	sync.mutex_lock(&g.mutex)
	defer sync.mutex_unlock(&g.mutex)

	tid := sync.current_thread_id()
	prev := g.current[tid]
	if ctx == nil {
		delete_key(&g.current, tid)
	} else {
		g.current[tid] = ctx
	}
	return prev
}

@(private)
globals_acquire :: proc(allocator: runtime.Allocator) {
	if g == nil {
		ng := new(Globals, allocator)
		ng.version = VERSION
		ng.ctx_size = size_of(Context)
		ng.node_size = size_of(Node)
		ng.allocator = allocator
		ng.current = make(map[int]^Context, 4, allocator)
		g = ng
	}
	sync.mutex_lock(&g.mutex)
	g.contexts += 1
	sync.mutex_unlock(&g.mutex)
}

@(private)
globals_release :: proc() {
	if g == nil {
		return
	}
	sync.mutex_lock(&g.mutex)
	g.contexts -= 1
	last := g.contexts <= 0
	sync.mutex_unlock(&g.mutex)

	if last {
		dying := g
		g = nil
		delete(dying.current)
		free(dying, dying.allocator)
	}
}

@(private)
ctx_of :: proc(loc := #caller_location) -> ^Context {
	assert(g != nil, "loom: init must run before any element call", loc)
	sync.mutex_lock(&g.mutex)
	defer sync.mutex_unlock(&g.mutex)
	ctx := g.current[sync.current_thread_id()]
	assert(ctx != nil, "loom: no current context on this thread, call make_current", loc)
	return ctx
}
