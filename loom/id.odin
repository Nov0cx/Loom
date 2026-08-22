package loom

import "base:runtime"

FNV_OFFSET :: 0xcbf29ce484222325
FNV_PRIME :: 0x100000001b3

ROOT_KEY :: "loom.root"

@(private)
fnv_bytes :: proc(h: u64, data: []byte) -> u64 {
	h := h
	for b in data {
		h ~= u64(b)
		h *= FNV_PRIME
	}
	return h
}

@(private)
fnv_u64 :: proc(h: u64, v: u64) -> u64 {
	v := v
	bytes := (^[8]byte)(&v)
	return fnv_bytes(h, bytes[:])
}

@(private)
finish :: proc(h: u64) -> Id {
	return Id(h) if h != 0 else Id(1)
}

hash_string :: proc(seed: Id, s: string) -> Id {
	h := fnv_u64(FNV_OFFSET, u64(seed))
	return finish(fnv_bytes(h, transmute([]byte)s))
}

hash_int :: proc(seed: Id, v: i64) -> Id {
	h := fnv_u64(FNV_OFFSET, u64(seed))
	return finish(fnv_u64(h, u64(v)))
}

hash_loc :: proc(seed: Id, loc: runtime.Source_Code_Location) -> Id {
	h := fnv_u64(FNV_OFFSET, u64(seed))
	h = fnv_bytes(h, transmute([]byte)loc.file_path)
	h = fnv_u64(h, u64(loc.line))
	h = fnv_u64(h, u64(loc.column))
	return finish(h)
}

push_id :: proc(key: string) {
	ctx := ctx_of()
	append(&ctx.id_stack, ctx.id_seed)
	ctx.id_seed = hash_string(ctx.id_seed, key)
}

push_id_int :: proc(key: i64) {
	ctx := ctx_of()
	append(&ctx.id_stack, ctx.id_seed)
	ctx.id_seed = hash_int(ctx.id_seed, key)
}

pop_id :: proc(loc := #caller_location) {
	ctx := ctx_of()
	assert(len(ctx.id_stack) > 0, "loom: pop_id without a matching push_id", loc)
	ctx.id_seed = pop(&ctx.id_stack)
}

current_id :: proc() -> Id {
	return ctx_of().id_seed
}
