package ui_sokol

import "core:c"
import sapp "../../third_party/sokol/sokol/app"
import sg "../../third_party/sokol/sokol/gfx"
import ui "../../loom"

MAX_FACES :: 32
DEFAULT_ARC_SEGMENTS :: 6
DEFAULT_ATLAS_SIZE :: 512
MAX_SHADOW_STEPS :: 12
INITIAL_VERTS :: 65536
INITIAL_IDXS :: 131072

Options :: struct {
	arc_segments: int,
	atlas_size:   int,
	dpi:          f32,
}

Tex_Info :: struct {
	img:   sg.Image,
	view:  sg.View,
	w, h:  int,
	owned: bool,
}

Backend :: struct {
	opts:        Options,
	err:         string,
	shader:      sg.Shader,
	pip:         sg.Pipeline,
	smp:         sg.Sampler,
	vbuf, ibuf:  sg.Buffer,
	vcap, icap:  int,
	want_v:      int,
	want_i:      int,
	white:       Tex_Info,
	verts:       [dynamic]Vertex,
	idxs:        [dynamic]u32,
	batches:     [dynamic]Batch,
	batch_first: u32,
	batch_view:  sg.View,
	batch_clip:  ui.Rect,
	clip:        [dynamic]ui.Rect,
	path_a:      [dynamic]ui.Vec2,
	path_b:      [dynamic]ui.Vec2,
	faces:       [MAX_FACES]Face,
	n_faces:     int,
	pages:       [dynamic]Page,
	glyphs:      map[Glyph_Key]Glyph,
	textures:    map[u32]Tex_Info,
	next_tex:    u32,
	win:         Win_State,
	cursor:      ui.Cursor,
	dpi:         f32,
	view:        ui.Vec2,
	fb:          ui.Vec2,
	scale:       f32,
	clear:       ui.Color,
	clipboard:   string,
}

@(private)
fail :: proc(b: ^Backend, msg: string) -> bool {
	if b.err == "" {
		b.err = msg
	}
	return false
}

init :: proc(b: ^Backend, opts: Options = {}) -> (ui.Backend, bool) {
	b^ = {}
	b.opts = opts
	if b.opts.arc_segments <= 0 {
		b.opts.arc_segments = DEFAULT_ARC_SEGMENTS
	}
	if b.opts.atlas_size <= 0 {
		b.opts.atlas_size = DEFAULT_ATLAS_SIZE
	}

	b.verts = make([dynamic]Vertex, 0, 4096)
	b.idxs = make([dynamic]u32, 0, 8192)
	b.batches = make([dynamic]Batch, 0, 64)
	b.clip = make([dynamic]ui.Rect, 0, 16)
	b.path_a = make([dynamic]ui.Vec2, 0, 64)
	b.path_b = make([dynamic]ui.Vec2, 0, 64)
	b.pages = make([dynamic]Page, 0, 2)
	b.glyphs = make(map[Glyph_Key]Glyph, 512)
	b.textures = make(map[u32]Tex_Info, 8)

	b.faces[0] = {
		ascent   = 0.8,
		descent  = -0.2,
		line_gap = 0,
	}
	b.n_faces = 1

	if !make_shader(b) {
		return ui.noop_backend(), false
	}
	if !make_pipeline(b, int(sapp.sample_count())) {
		return ui.noop_backend(), false
	}

	b.vcap = INITIAL_VERTS
	b.icap = INITIAL_IDXS
	b.vbuf = sg.make_buffer(
		{usage = {vertex_buffer = true, dynamic_update = true}, size = c.size_t(b.vcap * size_of(Vertex))},
	)
	b.ibuf = sg.make_buffer(
		{usage = {index_buffer = true, dynamic_update = true}, size = c.size_t(b.icap * size_of(u32))},
	)

	px := [4]u8{255, 255, 255, 255}
	img, view, ok := make_raw_texture(b, 1, 1, px[:])
	if !ok {
		return ui.noop_backend(), fail(b, "ui_sokol: could not create the white texture")
	}
	b.white = {
		img   = img,
		view  = view,
		w     = 1,
		h     = 1,
		owned = true,
	}

	b.dpi = backend_dpi(b)
	b.scale = b.dpi

	return ui.Backend {
			measure_run = measure_run,
			font_metrics = font_metrics,
			set_cursor = set_cursor,
			clipboard_get = clipboard_get,
			clipboard_set = clipboard_set,
			user = b,
			viewports = nil,
		},
		true
}

destroy :: proc(b: ^Backend) {
	for &p in b.pages {
		sg.destroy_view(p.view)
		sg.destroy_image(p.img)
		delete(p.pixels)
	}
	delete(b.pages)
	delete(b.glyphs)

	for _, t in b.textures {
		if t.owned {
			sg.destroy_view(t.view)
			sg.destroy_image(t.img)
		}
	}
	delete(b.textures)

	for i in 0 ..< b.n_faces {
		if b.faces[i].owned {
			delete(b.faces[i].data)
		}
	}

	sg.destroy_view(b.white.view)
	sg.destroy_image(b.white.img)
	sg.destroy_buffer(b.vbuf)
	sg.destroy_buffer(b.ibuf)
	sg.destroy_sampler(b.smp)
	sg.destroy_pipeline(b.pip)
	sg.destroy_shader(b.shader)

	delete(b.verts)
	delete(b.idxs)
	delete(b.batches)
	delete(b.clip)
	delete(b.path_a)
	delete(b.path_b)
	b^ = {}
}

make_raw_texture :: proc(
	b: ^Backend,
	w, h: int,
	pixels: []u8,
) -> (
	img: sg.Image,
	view: sg.View,
	ok: bool,
) {
	desc := sg.Image_Desc {
		type         = ._2D,
		width        = i32(w),
		height       = i32(h),
		num_slices   = 1,
		num_mipmaps  = 1,
		pixel_format = .RGBA8,
		sample_count = 1,
	}
	if pixels != nil {
		desc.usage = {immutable = true}
		desc.data.mip_levels[0] = {
			ptr  = raw_data(pixels),
			size = c.size_t(len(pixels)),
		}
	} else {
		desc.usage = {dynamic_update = true}
	}

	img = sg.make_image(desc)
	if sg.query_image_state(img) != .VALID {
		return {}, {}, false
	}
	view = sg.make_view({texture = {image = img}})
	if sg.query_view_state(view) != .VALID {
		sg.destroy_image(img)
		return {}, {}, false
	}
	return img, view, true
}

register_texture :: proc(b: ^Backend, img: sg.Image, w, h: int) -> ui.Texture {
	view := sg.make_view({texture = {image = img}})
	b.next_tex += 1
	b.textures[b.next_tex] = {
		img   = img,
		view  = view,
		w     = w,
		h     = h,
		owned = false,
	}
	return ui.Texture(b.next_tex)
}

load_texture :: proc(b: ^Backend, w, h: int, rgba: []u8) -> ui.Texture {
	assert(len(rgba) >= w * h * 4, "ui_sokol: pixel buffer is smaller than the texture")
	img, view, ok := make_raw_texture(b, w, h, rgba)
	if !ok {
		return 0
	}
	b.next_tex += 1
	b.textures[b.next_tex] = {
		img   = img,
		view  = view,
		w     = w,
		h     = h,
		owned = true,
	}
	return ui.Texture(b.next_tex)
}

set_clear_color :: proc(b: ^Backend, col: ui.Color) {
	b.clear = col
}

@(private)
backend_dpi :: proc(b: ^Backend) -> f32 {
	if b.opts.dpi > 0 {
		return b.opts.dpi
	}
	s := sapp.dpi_scale()
	return s > 0 ? s : 1
}

@(rodata)
CURSORS := [ui.Cursor]sapp.Mouse_Cursor {
	.Default     = .DEFAULT,
	.Pointer     = .POINTING_HAND,
	.Text        = .IBEAM,
	.Resize_H    = .RESIZE_EW,
	.Resize_V    = .RESIZE_NS,
	.Grab        = .POINTING_HAND,
	.Grabbing    = .RESIZE_ALL,
	.Not_Allowed = .NOT_ALLOWED,
}

set_cursor :: proc(cur: ui.Cursor, user: rawptr) {
	b := (^Backend)(user)
	if b.cursor == cur {
		return
	}
	b.cursor = cur
	sapp.set_mouse_cursor(CURSORS[cur])
}

clipboard_get :: proc(user: rawptr) -> string {
	b := (^Backend)(user)
	b.clipboard = string(sapp.get_clipboard_string())
	return b.clipboard
}

clipboard_set :: proc(text: string, user: rawptr) {
	buf := make([]byte, len(text) + 1, context.temp_allocator)
	copy(buf, text)
	buf[len(text)] = 0
	sapp.set_clipboard_string(cstring(raw_data(buf)))
}
