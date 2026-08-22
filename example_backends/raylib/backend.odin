package ui_raylib

import rl "vendor:raylib"
import ui "../../loom"

MAX_FACES :: 32
DEFAULT_ARC_SEGMENTS :: 6
MAX_SHADOW_STEPS :: 12

Options :: struct {
	arc_segments: int,
	dpi:          f32,
}

Backend :: struct {
	opts:     Options,
	faces:    [MAX_FACES]Face,
	n_faces:  int,
	textures: map[u32]rl.Texture2D,
	clip:     [dynamic]rl.Rectangle,
	path_a:   [dynamic]rl.Vector2,
	path_b:   [dynamic]rl.Vector2,
	scratch:  [dynamic]byte,
	text_buf: [64]byte,
	text_len: int,
	dpi:      f32,
	cursor:   ui.Cursor,
}

init :: proc(b: ^Backend, opts: Options = {}) -> ui.Backend {
	b^ = {}
	b.opts = opts
	if b.opts.arc_segments <= 0 {
		b.opts.arc_segments = DEFAULT_ARC_SEGMENTS
	}

	b.textures = make(map[u32]rl.Texture2D, 8)
	b.clip = make([dynamic]rl.Rectangle, 0, 16)
	b.path_a = make([dynamic]rl.Vector2, 0, 64)
	b.path_b = make([dynamic]rl.Vector2, 0, 64)
	b.scratch = make([dynamic]byte, 0, 256)

	b.dpi = opts.dpi > 0 ? opts.dpi : 1
	b.faces[0] = {ascent = 0.75, descent = -0.25}
	b.faces[0].baked = make(map[i32]rl.Font)
	b.n_faces = 1

	return ui.Backend {
		measure_run = measure_run,
		font_metrics = font_metrics,
		set_cursor = set_cursor,
		clipboard_get = clipboard_get,
		clipboard_set = clipboard_set,
		user = b,
		viewports = nil,
	}
}

destroy :: proc(b: ^Backend) {
	for i in 0 ..< b.n_faces {
		f := &b.faces[i]
		for _, font in f.baked {
			if f.data != nil {
				rl.UnloadFont(font)
			}
		}
		delete(f.baked)
		if f.owned {
			delete(f.data)
		}
	}
	delete(b.textures)
	delete(b.clip)
	delete(b.path_a)
	delete(b.path_b)
	delete(b.scratch)
	b^ = {}
}

register_texture :: proc(b: ^Backend, tex: rl.Texture2D) -> ui.Texture {
	b.textures[tex.id] = tex
	return ui.Texture(tex.id)
}

set_cursor :: proc(cur: ui.Cursor, user: rawptr) {
	b := (^Backend)(user)
	if b.cursor == cur {
		return
	}
	b.cursor = cur

	shape: rl.MouseCursor
	switch cur {
	case .Default:
		shape = .DEFAULT
	case .Pointer:
		shape = .POINTING_HAND
	case .Text:
		shape = .IBEAM
	case .Resize_H:
		shape = .RESIZE_EW
	case .Resize_V:
		shape = .RESIZE_NS
	case .Grab:
		shape = .POINTING_HAND
	case .Grabbing:
		shape = .RESIZE_ALL
	case .Not_Allowed:
		shape = .NOT_ALLOWED
	}
	rl.SetMouseCursor(shape)
}

clipboard_get :: proc(user: rawptr) -> string {
	return string(rl.GetClipboardText())
}

clipboard_set :: proc(text: string, user: rawptr) {
	b := (^Backend)(user)
	rl.SetClipboardText(cstr(b, text))
}

@(private)
cstr :: proc(b: ^Backend, s: string) -> cstring {
	clear(&b.scratch)
	append(&b.scratch, s)
	append(&b.scratch, 0)
	return cstring(raw_data(b.scratch))
}
