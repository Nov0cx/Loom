package ui_raylib

import "core:c"
import "core:math"
import "core:os"
import rl "vendor:raylib"
import stbtt "vendor:stb/truetype"
import ui "../../loom"

DEFAULT_FONT :: ui.Font(1)
MIN_PX :: 6
MAX_PX :: 256

Face :: struct {
	data:     []byte,
	info:     stbtt.fontinfo,
	ascent:   f32,
	descent:  f32,
	line_gap: f32,
	spacing:  f32,
	owned:    bool,
	baked:    map[i32]rl.Font,
}

load_face :: proc(b: ^Backend, ttf: []byte, spacing: f32 = 0) -> ui.Font {
	assert(b.n_faces < MAX_FACES, "ui_raylib: too many faces")
	f := &b.faces[b.n_faces]
	f^ = {data = ttf, spacing = spacing}
	f.baked = make(map[i32]rl.Font)

	if stbtt.InitFont(&f.info, raw_data(ttf), 0) {
		a, d, g: c.int
		stbtt.GetFontVMetrics(&f.info, &a, &d, &g)
		s := stbtt.ScaleForPixelHeight(&f.info, 1)
		f.ascent, f.descent, f.line_gap = f32(a) * s, f32(d) * s, f32(g) * s
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
face_of :: proc(b: ^Backend, h: ui.Font) -> ^Face {
	i := int(h) - 1
	if i < 0 || i >= b.n_faces {
		i = 0
	}
	return &b.faces[i]
}

@(private)
baked :: proc(b: ^Backend, f: ^Face, size: f32) -> rl.Font {
	px := i32(clamp(int(math.round(size * b.dpi)), MIN_PX, MAX_PX))
	if font, ok := f.baked[px]; ok {
		return font
	}

	font: rl.Font
	if f.data == nil {
		font = rl.GetFontDefault()
	} else {
		font = rl.LoadFontFromMemory(".ttf", raw_data(f.data), c.int(len(f.data)), px, nil, 0)
		rl.SetTextureFilter(font.texture, .BILINEAR)
	}
	f.baked[px] = font
	return font
}

font_metrics :: proc(font: ui.Font, size: f32, user: rawptr) -> ui.Font_Metrics {
	b := (^Backend)(user)
	f := face_of(b, font)
	return {ascent = f.ascent * size, descent = f.descent * size, line_gap = f.line_gap * size}
}

@(private)
tracking_of :: proc(f: ^Face, size, spacing: f32) -> f32 {
	return spacing + f.spacing * size
}

measure_run :: proc(font: ui.Font, size: f32, text: string, spacing: f32, user: rawptr) -> f32 {
	if text == "" || size <= 0 {
		return 0
	}
	b := (^Backend)(user)
	f := face_of(b, font)
	fnt := baked(b, f, size)
	return rl.MeasureTextEx(fnt, cstr(b, text), size, tracking_of(f, size, spacing)).x
}
