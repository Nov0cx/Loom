package ui_dx11

import win "core:sys/windows"
import d3d "vendor:directx/d3d11"
import "vendor:directx/dxgi"
import ui "../../loom"

MAX_FACES :: 32
DEFAULT_ARC_SEGMENTS :: 6
DEFAULT_ATLAS_SIZE :: 1024
DEFAULT_MSAA :: 4
MAX_SHADOW_STEPS :: 12

Options :: struct {
	arc_segments: int,
	atlas_size:   int,
	dpi:          f32,
	msaa:         int,
	no_vsync:     bool,
}

Target :: struct {
	hwnd:    win.HWND,
	swap:    ^dxgi.ISwapChain,
	rtv:     ^d3d.IRenderTargetView,
	w, h:    int,
	resized: bool,
}

Tex_Info :: struct {
	tex:   ^d3d.ITexture2D,
	srv:   ^d3d.IShaderResourceView,
	w, h:  int,
	owned: bool,
}

Backend :: struct {
	opts:        Options,
	err:         string,
	device:      ^d3d.IDevice,
	dctx:        ^d3d.IDeviceContext,
	factory:     ^dxgi.IFactory,
	vs:          ^d3d.IVertexShader,
	ps:          ^d3d.IPixelShader,
	input:       ^d3d.IInputLayout,
	cbuf:        ^d3d.IBuffer,
	blend:       ^d3d.IBlendState,
	raster:      ^d3d.IRasterizerState,
	depth:       ^d3d.IDepthStencilState,
	sampler:     ^d3d.ISamplerState,
	samples:     u32,
	vbuf, ibuf:  Buf,
	white:       Tex_Info,
	main:        Target,
	target:      ^Target,
	verts:       [dynamic]Vertex,
	idxs:        [dynamic]u32,
	batches:     [dynamic]Batch,
	batch_first: u32,
	batch_srv:   ^d3d.IShaderResourceView,
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
	class:       win.ATOM,
	hinst:       win.HINSTANCE,
	wins:        map[win.HWND]^Win_State,
	cursors:     [ui.Cursor]win.HCURSOR,
	cursor:      ui.Cursor,
	viewports:   map[ui.Viewport_Handle]^Vp,
	next_vp:     u64,
	dpi:         f32,
	view:        ui.Vec2,
	fb:          ui.Vec2,
	scale:       f32,
	clear:       ui.Color,
	time:        f64,
	clipboard:   string,
}

init :: proc(b: ^Backend, hwnd: win.HWND, opts: Options = {}) -> (ui.Backend, bool) {
	b^ = {}
	b.opts = opts
	if b.opts.arc_segments <= 0 {
		b.opts.arc_segments = DEFAULT_ARC_SEGMENTS
	}
	if b.opts.atlas_size <= 0 {
		b.opts.atlas_size = DEFAULT_ATLAS_SIZE
	}
	if b.opts.msaa <= 0 {
		b.opts.msaa = DEFAULT_MSAA
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
	b.wins = make(map[win.HWND]^Win_State, 4)
	b.viewports = make(map[ui.Viewport_Handle]^Vp, 4)

	b.faces[0] = {
		ascent   = 0.8,
		descent  = -0.2,
		line_gap = 0,
	}
	b.n_faces = 1

	SHAPES := [ui.Cursor]rawptr {
		.Default     = win._IDC_ARROW,
		.Pointer     = win._IDC_HAND,
		.Text        = win._IDC_IBEAM,
		.Resize_H    = win._IDC_SIZEWE,
		.Resize_V    = win._IDC_SIZENS,
		.Grab        = win._IDC_HAND,
		.Grabbing    = win._IDC_SIZEALL,
		.Not_Allowed = win._IDC_NO,
	}
	for shape, cur in SHAPES {
		b.cursors[cur] = win.LoadCursorW(nil, win.LPCWSTR(shape))
	}

	if !make_device(b) {
		return ui.noop_backend(), false
	}
	b.samples = pick_samples(b, b.opts.msaa)

	if !make_shaders(b) || !make_states(b) || !make_white(b) {
		return ui.noop_backend(), false
	}

	if !register_class(b) {
		fail(b, "ui_dx11: could not register the window class")
		return ui.noop_backend(), false
	}

	if !make_swapchain(b, &b.main, hwnd) {
		fail(b, "ui_dx11: could not create the swap chain")
		return ui.noop_backend(), false
	}
	b.target = &b.main

	adopt_window(b, hwnd)
	b.dpi = window_dpi(b, hwnd)
	b.time = time_now()

	return ui.Backend {
			measure_run = measure_run,
			font_metrics = font_metrics,
			set_cursor = set_cursor,
			clipboard_get = clipboard_get,
			clipboard_set = clipboard_set,
			user = b,
			viewports = viewport_ops(),
		},
		true
}

destroy :: proc(b: ^Backend) {
	for _, v in b.viewports {
		destroy_target(b, &v.target)
		win.DestroyWindow(v.hwnd)
		free(v)
	}
	delete(b.viewports)

	for _, w in b.wins {
		free(w)
	}
	delete(b.wins)

	destroy_target(b, &b.main)

	for &p in b.pages {
		if p.srv != nil {
			p.srv->Release()
		}
		if p.tex != nil {
			p.tex->Release()
		}
		delete(p.pixels)
	}
	delete(b.pages)
	delete(b.glyphs)

	for _, t in b.textures {
		if !t.owned {
			continue
		}
		if t.srv != nil {
			t.srv->Release()
		}
		if t.tex != nil {
			t.tex->Release()
		}
	}
	delete(b.textures)

	for i in 0 ..< b.n_faces {
		if b.faces[i].owned {
			delete(b.faces[i].data)
		}
	}

	release(b.white.srv)
	release(b.white.tex)
	release(b.vbuf.buf)
	release(b.ibuf.buf)
	release(b.cbuf)
	release(b.sampler)
	release(b.depth)
	release(b.raster)
	release(b.blend)
	release(b.input)
	release(b.ps)
	release(b.vs)


	if b.dctx != nil {
		b.dctx->ClearState()
		b.dctx->Flush()
		b.dctx->Release()
	}
	release(b.factory)
	release(b.device)

	delete(b.verts)
	delete(b.idxs)
	delete(b.batches)
	delete(b.clip)
	delete(b.path_a)
	delete(b.path_b)
	delete(b.clipboard)
	b^ = {}
}

@(private)
release :: proc(obj: ^$T) {
	if obj != nil {
		obj->Release()
	}
}

register_texture :: proc(
	b: ^Backend,
	srv: ^d3d.IShaderResourceView,
	w, h: int,
) -> ui.Texture {
	b.next_tex += 1
	b.textures[b.next_tex] = {
		srv   = srv,
		w     = w,
		h     = h,
		owned = false,
	}
	return ui.Texture(b.next_tex)
}

load_texture :: proc(b: ^Backend, w, h: int, rgba: []u8) -> ui.Texture {
	assert(len(rgba) >= w * h * 4, "ui_dx11: pixel buffer is smaller than the texture")
	tex, srv, ok := make_raw_texture(b, w, h, rgba)
	if !ok {
		return 0
	}
	b.next_tex += 1
	b.textures[b.next_tex] = {
		tex   = tex,
		srv   = srv,
		w     = w,
		h     = h,
		owned = true,
	}
	return ui.Texture(b.next_tex)
}

set_cursor :: proc(cur: ui.Cursor, user: rawptr) {
	b := (^Backend)(user)
	if b.cursor == cur {
		return
	}
	b.cursor = cur
	win.SetCursor(b.cursors[cur])
}

clipboard_get :: proc(user: rawptr) -> string {
	b := (^Backend)(user)
	if !open_clipboard(b.main.hwnd) {
		return ""
	}
	defer win.CloseClipboard()

	h := win.GetClipboardData(win.CF_UNICODETEXT)
	if h == nil {
		return ""
	}
	ptr := win.GlobalLock(win.HGLOBAL(h))
	if ptr == nil {
		return ""
	}
	defer win.GlobalUnlock(win.HGLOBAL(h))

	wide := ([^]u16)(ptr)
	n := 0
	for wide[n] != 0 {
		n += 1
	}

	delete(b.clipboard)
	b.clipboard, _ = win.utf16_to_utf8(wide[:n], context.allocator)
	return b.clipboard
}

clipboard_set :: proc(text: string, user: rawptr) {
	b := (^Backend)(user)
	if !open_clipboard(b.main.hwnd) {
		return
	}
	defer win.CloseClipboard()
	win.EmptyClipboard()

	wide := win.utf8_to_utf16(text, context.temp_allocator)
	bytes := (len(wide) + 1) * size_of(u16)

	mem := win.GlobalAlloc(win.GMEM_MOVEABLE, win.SIZE_T(bytes))
	if mem == nil {
		return
	}
	ptr := win.GlobalLock(win.HGLOBAL(mem))
	if ptr == nil {
		win.GlobalFree(mem)
		return
	}
	dst := ([^]u16)(ptr)
	for c, i in wide {
		dst[i] = c
	}
	dst[len(wide)] = 0
	win.GlobalUnlock(win.HGLOBAL(mem))

	if win.SetClipboardData(win.CF_UNICODETEXT, win.HANDLE(mem)) == nil {
		win.GlobalFree(mem)
	}
}

@(private)
open_clipboard :: proc(hwnd: win.HWND) -> bool {
	for _ in 0 ..< 5 {
		if win.OpenClipboard(hwnd) {
			return true
		}
	}
	return false
}
