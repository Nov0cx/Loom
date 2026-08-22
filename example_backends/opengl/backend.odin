package ui_opengl

import "core:c"
import gl "vendor:OpenGL"
import "vendor:glfw"
import ui "../../loom"

MAX_FACES :: 32
DEFAULT_ARC_SEGMENTS :: 6
DEFAULT_ATLAS_SIZE :: 1024
MAX_SHADOW_STEPS :: 12

Options :: struct {
	arc_segments: int,
	atlas_size:   int,
	dpi:          f32,
}

Win_State :: struct {
	vao:            u32,
	keys_down:      ui.Key_Set,
	keys_pressed:   ui.Key_Set,
	mods:           ui.Mod_Set,
	mouse_down:     ui.Mouse_Set,
	mouse_pressed:  ui.Mouse_Set,
	mouse_released: ui.Mouse_Set,
	wheel:          ui.Vec2,
	text_buf:       [64]byte,
	text_out:       [64]byte,
	text_len:       int,
	inside:         bool,
}

Tex_Info :: struct {
	id:   u32,
	w, h: int,
}

Backend :: struct {
	win:       glfw.WindowHandle,
	target:    glfw.WindowHandle,
	opts:      Options,
	prog:      u32,
	u_size:    i32,
	u_tex:     i32,
	vbo, ibo:  u32,
	white:     u32,
	verts:     [dynamic]Vertex,
	idxs:      [dynamic]u32,
	batch_tex: u32,
	clip:      [dynamic]ui.Rect,
	path_a:    [dynamic]ui.Vec2,
	path_b:    [dynamic]ui.Vec2,
	faces:     [MAX_FACES]Face,
	n_faces:   int,
	pages:     [dynamic]Page,
	glyphs:    map[Glyph_Key]Glyph,
	textures:  map[u32]Tex_Info,
	wins:      map[glfw.WindowHandle]^Win_State,
	cursors:   [ui.Cursor]glfw.CursorHandle,
	cursor:    ui.Cursor,
	viewports: map[ui.Viewport_Handle]^Vp,
	next_vp:   u64,
	dpi:       f32,
	view:      ui.Vec2,
	fb:        ui.Vec2,
	scale:     f32,
	clear:     ui.Color,
	time:      f64,
	clipboard: string,
}

init :: proc(b: ^Backend, win: glfw.WindowHandle, opts: Options = {}) -> ui.Backend {
	b^ = {}
	b.win = win
	b.target = win
	b.opts = opts
	if b.opts.arc_segments <= 0 {
		b.opts.arc_segments = DEFAULT_ARC_SEGMENTS
	}
	if b.opts.atlas_size <= 0 {
		b.opts.atlas_size = DEFAULT_ATLAS_SIZE
	}

	glfw.MakeContextCurrent(win)
	gl.load_up_to(3, 3, glfw.gl_set_proc_address)

	prog, ok := make_program()
	assert(ok, "ui_opengl: the ui shader did not compile")
	b.prog = prog
	b.u_size = gl.GetUniformLocation(prog, "u_size")
	b.u_tex = gl.GetUniformLocation(prog, "u_tex")
	make_buffers(b)

	b.verts = make([dynamic]Vertex, 0, 4096)
	b.idxs = make([dynamic]u32, 0, 8192)
	b.clip = make([dynamic]ui.Rect, 0, 16)
	b.path_a = make([dynamic]ui.Vec2, 0, 64)
	b.path_b = make([dynamic]ui.Vec2, 0, 64)
	b.pages = make([dynamic]Page, 0, 2)
	b.glyphs = make(map[Glyph_Key]Glyph, 512)
	b.textures = make(map[u32]Tex_Info, 8)
	b.wins = make(map[glfw.WindowHandle]^Win_State, 4)
	b.viewports = make(map[ui.Viewport_Handle]^Vp, 4)

	b.faces[0] = {ascent = 0.8, descent = -0.2, line_gap = 0}
	b.n_faces = 1

	SHAPES := [ui.Cursor]c.int {
		.Default     = glfw.ARROW_CURSOR,
		.Pointer     = glfw.POINTING_HAND_CURSOR,
		.Text        = glfw.IBEAM_CURSOR,
		.Resize_H    = glfw.RESIZE_EW_CURSOR,
		.Resize_V    = glfw.RESIZE_NS_CURSOR,
		.Grab        = glfw.POINTING_HAND_CURSOR,
		.Grabbing    = glfw.RESIZE_ALL_CURSOR,
		.Not_Allowed = glfw.NOT_ALLOWED_CURSOR,
	}
	for shape, cur in SHAPES {
		b.cursors[cur] = glfw.CreateStandardCursor(shape)
	}

	adopt_window(b, win)
	b.dpi = window_dpi(b, win)
	b.time = glfw.GetTime()

	return ui.Backend {
		measure_run = measure_run,
		font_metrics = font_metrics,
		set_cursor = set_cursor,
		clipboard_get = clipboard_get,
		clipboard_set = clipboard_set,
		user = b,
		viewports = viewport_ops(),
	}
}

destroy :: proc(b: ^Backend) {
	glfw.MakeContextCurrent(b.win)

	for _, v in b.viewports {
		glfw.DestroyWindow(v.win)
		free(v)
	}
	delete(b.viewports)

	for _, w in b.wins {
		free(w)
	}
	delete(b.wins)

	for cur in ui.Cursor {
		if b.cursors[cur] != nil {
			glfw.DestroyCursor(b.cursors[cur])
		}
	}

	for &p in b.pages {
		gl.DeleteTextures(1, &p.tex)
		delete(p.pixels)
	}
	delete(b.pages)
	delete(b.glyphs)

	for i in 0 ..< b.n_faces {
		if b.faces[i].owned {
			delete(b.faces[i].data)
		}
	}

	gl.DeleteBuffers(1, &b.vbo)
	gl.DeleteBuffers(1, &b.ibo)
	gl.DeleteTextures(1, &b.white)
	gl.DeleteProgram(b.prog)

	delete(b.verts)
	delete(b.idxs)
	delete(b.clip)
	delete(b.path_a)
	delete(b.path_b)
	delete(b.textures)
	b^ = {}
}

register_texture :: proc(b: ^Backend, id: u32, w, h: int) -> ui.Texture {
	b.textures[id] = {id = id, w = w, h = h}
	return ui.Texture(id)
}

load_texture :: proc(b: ^Backend, w, h: int, rgba: []u8) -> ui.Texture {
	assert(len(rgba) >= w * h * 4, "ui_opengl: pixel buffer is smaller than the texture")
	id := make_texture(w, h, raw_data(rgba))
	return register_texture(b, id, w, h)
}

set_cursor :: proc(cur: ui.Cursor, user: rawptr) {
	b := (^Backend)(user)
	if b.cursor == cur {
		return
	}
	b.cursor = cur
	glfw.SetCursor(b.win, b.cursors[cur])
	for _, v in b.viewports {
		glfw.SetCursor(v.win, b.cursors[cur])
	}
}

clipboard_get :: proc(user: rawptr) -> string {
	b := (^Backend)(user)
	b.clipboard = glfw.GetClipboardString(b.win)
	return b.clipboard
}

clipboard_set :: proc(text: string, user: rawptr) {
	b := (^Backend)(user)
	glfw.SetClipboardString(b.win, cstr(text))
}

@(private)
cstr :: proc(s: string) -> cstring {
	buf := make([]byte, len(s) + 1, context.temp_allocator)
	copy(buf, s)
	buf[len(s)] = 0
	return cstring(raw_data(buf))
}

@(private)
window_dpi :: proc(b: ^Backend, win: glfw.WindowHandle) -> f32 {
	if b.opts.dpi > 0 {
		return b.opts.dpi
	}
	fw, _ := glfw.GetFramebufferSize(win)
	ww, _ := glfw.GetWindowSize(win)
	if ww > 0 && fw > 0 {
		return f32(fw) / f32(ww)
	}
	sx, _ := glfw.GetWindowContentScale(win)
	return sx > 0 ? sx : 1
}
