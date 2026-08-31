package ui_sokol

import "core:c"
import "core:math"
import "core:os"
import sg "../../third_party/sokol/sokol/gfx"
import stbtt "vendor:stb/truetype"
import ui "../../loom"

DEFAULT_FONT :: ui.Font(1)
MIN_PX :: 6
MAX_PX :: 256
GLYPH_PAD :: 1

Face :: struct {
	data:     []byte,
	info:     stbtt.fontinfo,
	ascent:   f32,
	descent:  f32,
	line_gap: f32,
	spacing:  f32,
	owned:    bool,
	loaded:   bool,
}

Page :: struct {
	img:                sg.Image,
	view:               sg.View,
	w, h:               int,
	pixels:             []u8,
	x, y:               int,
	row_h:              int,
	dirty:              bool,
}

Glyph_Key :: struct {
	face: u16,
	px:   u16,
	r:    rune,
}

Glyph :: struct {
	page:           int,
	u0, v0, u1, v1: f32,
	x0, y0:         f32,
	w, h:           f32,
	drawable:       bool,
}

load_face :: proc(b: ^Backend, ttf: []byte, spacing: f32 = 0) -> ui.Font {
	assert(b.n_faces < MAX_FACES, "ui_sokol: too many faces")
	f := &b.faces[b.n_faces]
	f^ = {
		data    = ttf,
		spacing = spacing,
	}

	if stbtt.InitFont(&f.info, raw_data(ttf), 0) {
		a, d, g: c.int
		stbtt.GetFontVMetrics(&f.info, &a, &d, &g)
		s := stbtt.ScaleForPixelHeight(&f.info, 1)
		f.ascent, f.descent, f.line_gap = f32(a) * s, f32(d) * s, f32(g) * s
		f.loaded = true
	} else {
		f.ascent, f.descent = 0.8, -0.2
	}

	b.n_faces += 1
	return ui.Font(b.n_faces)
}

load_face_file :: proc(b: ^Backend, path: string, spacing: f32 = 0) -> (ui.Font, bool) {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		return DEFAULT_FONT, false
	}
	f := load_face(b, data, spacing)
	b.faces[int(f) - 1].owned = true
	return f, true
}

@(private)
face_of :: proc(b: ^Backend, h: ui.Font) -> (^Face, int) {
	i := int(h) - 1
	if i < 0 || i >= b.n_faces {
		i = 0
	}
	return &b.faces[i], i
}

font_metrics :: proc(font: ui.Font, size: f32, user: rawptr) -> ui.Font_Metrics {
	b := (^Backend)(user)
	f, _ := face_of(b, font)
	return {ascent = f.ascent * size, descent = f.descent * size, line_gap = f.line_gap * size}
}

@(private)
advance_of :: proc(f: ^Face, size: f32, r: rune) -> f32 {
	if !f.loaded {
		return size * 0.5
	}
	adv, lsb: c.int
	stbtt.GetCodepointHMetrics(&f.info, r, &adv, &lsb)
	return f32(adv) * stbtt.ScaleForPixelHeight(&f.info, size)
}

@(private)
tracking_of :: proc(f: ^Face, size, spacing: f32) -> f32 {
	return spacing + f.spacing * size
}

measure_run :: proc(font: ui.Font, size: f32, text: string, spacing: f32, user: rawptr) -> f32 {
	b := (^Backend)(user)
	f, _ := face_of(b, font)
	track := tracking_of(f, size, spacing)

	w: f32
	for r in text {
		w += advance_of(f, size, r) + track
	}
	return w
}

@(private)
atlas_px :: proc(b: ^Backend, size: f32) -> int {
	return clamp(int(math.round(size * b.dpi)), MIN_PX, MAX_PX)
}

@(private)
new_page :: proc(b: ^Backend) -> int {
	n := b.opts.atlas_size
	p := Page {
		w      = n,
		h      = n,
		pixels = make([]u8, n * n * 4),
	}
	img, view, ok := make_raw_texture(b, n, n, nil)
	if !ok {
		delete(p.pixels)
		return -1
	}
	p.img, p.view = img, view
	p.dirty = true
	append(&b.pages, p)
	return len(b.pages) - 1
}

@(private)
pack_rect :: proc(b: ^Backend, w, h: int) -> (page, x, y: int, ok: bool) {
	if w > b.opts.atlas_size || h > b.opts.atlas_size {
		return 0, 0, 0, false
	}
	if len(b.pages) == 0 && new_page(b) < 0 {
		return 0, 0, 0, false
	}

	for attempt in 0 ..< 2 {
		p := &b.pages[len(b.pages) - 1]
		if p.x + w + GLYPH_PAD > p.w {
			p.x = 0
			p.y += p.row_h + GLYPH_PAD
			p.row_h = 0
		}
		if p.y + h + GLYPH_PAD <= p.h {
			px, py := p.x, p.y
			p.x += w + GLYPH_PAD
			p.row_h = max(p.row_h, h)
			return len(b.pages) - 1, px, py, true
		}
		if attempt == 0 && new_page(b) < 0 {
			return 0, 0, 0, false
		}
	}
	return 0, 0, 0, false
}

@(private)
glyph_of :: proc(b: ^Backend, font: ui.Font, px: int, r: rune) -> Glyph {
	f, fi := face_of(b, font)
	key := Glyph_Key{u16(fi), u16(px), r}
	if g, ok := b.glyphs[key]; ok {
		return g
	}

	g: Glyph
	if !f.loaded {
		b.glyphs[key] = g
		return g
	}

	scale := stbtt.ScaleForPixelHeight(&f.info, f32(px))
	x0, y0, x1, y1: c.int
	stbtt.GetCodepointBitmapBox(&f.info, r, scale, scale, &x0, &y0, &x1, &y1)
	w, h := int(x1 - x0), int(y1 - y0)

	if w > 0 && h > 0 {
		page, ax, ay, ok := pack_rect(b, w, h)
		if ok {
			cov := make([]u8, w * h, context.temp_allocator)
			stbtt.MakeCodepointBitmap(
				&f.info,
				raw_data(cov),
				c.int(w),
				c.int(h),
				c.int(w),
				scale,
				scale,
				r,
			)

			p := &b.pages[page]
			for row in 0 ..< h {
				dst := ((ay + row) * p.w + ax) * 4
				src := row * w
				for col in 0 ..< w {
					p.pixels[dst + col * 4 + 0] = 255
					p.pixels[dst + col * 4 + 1] = 255
					p.pixels[dst + col * 4 + 2] = 255
					p.pixels[dst + col * 4 + 3] = cov[src + col]
				}
			}
			p.dirty = true

			g.page = page
			g.drawable = true
			g.x0, g.y0 = f32(x0), f32(y0)
			g.w, g.h = f32(w), f32(h)
			g.u0 = f32(ax) / f32(p.w)
			g.v0 = f32(ay) / f32(p.h)
			g.u1 = f32(ax + w) / f32(p.w)
			g.v1 = f32(ay + h) / f32(p.h)
		}
	}

	b.glyphs[key] = g
	return g
}

@(private)
flush_atlas :: proc(b: ^Backend) {
	for &p in b.pages {
		if !p.dirty {
			continue
		}
		data: sg.Image_Data
		data.mip_levels[0] = {ptr = raw_data(p.pixels), size = c.size_t(len(p.pixels))}
		sg.update_image(p.img, data)
		p.dirty = false
	}
}
