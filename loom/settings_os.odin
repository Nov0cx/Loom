#+build !freestanding
#+build !js
package loom

import "core:os"
import "core:strings"

settings_load_file :: proc(path: string) -> bool {
	ctx := ctx_of()
	data, err := os.read_entire_file_from_path(path, ctx.frame_allocator)
	if err != nil {
		return false
	}
	return settings_load_ctx(ctx, data)
}

settings_save_file :: proc(path: string) -> bool {
	ctx := ctx_of()
	b := strings.builder_make(ctx.frame_allocator)
	settings_save_ctx(ctx, strings.to_writer(&b))

	tmp := strings.concatenate({path, ".tmp"}, ctx.frame_allocator)
	if err := os.write_entire_file(tmp, transmute([]byte)strings.to_string(b)); err != nil {
		return false
	}
	if err := os.rename(tmp, path); err != nil {
		os.remove(tmp)
		return false
	}
	ctx.settings_timer = 0
	return true
}

settings_auto_save :: proc(path: string) -> bool {
	ctx := ctx_of()
	if !ctx.settings_dirty {
		ctx.settings_timer = 0
		return false
	}
	ctx.settings_timer += ctx.input.dt
	if ctx.settings_timer < ctx.cfg.settings_rate {
		return false
	}
	return settings_save_file(path)
}
