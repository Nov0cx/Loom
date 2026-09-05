package loom

Id :: distinct u64
Font :: distinct u32
Texture :: distinct u32

Vec2 :: [2]f32
Rect :: struct {
	x, y, w, h: f32,
}

Color :: distinct [4]u8

Version :: struct {
	major, minor: u32,
}

VERSION :: Version{0, 2}

rgb :: proc(r, g, b: u8) -> Color {
	return {r, g, b, 255}
}

rgba :: proc(r, g, b, a: u8) -> Color {
	return {r, g, b, a}
}

hex :: proc(v: u32, a: u8 = 255) -> Color {
	return {u8(v >> 16), u8(v >> 8), u8(v), a}
}

fade :: proc(c: Color, alpha: f32) -> Color {
	a := f32(c[3]) * clamp(alpha, 0, 1)
	return {c[0], c[1], c[2], u8(a + 0.5)}
}

Edges :: struct {
	l, t, r, b: f32,
}

Radius :: struct {
	tl, tr, br, bl: f32,
}

all :: proc(v: f32) -> Edges {
	return {v, v, v, v}
}

xy :: proc(x, y: f32) -> Edges {
	return {x, y, x, y}
}

ltrb :: proc(l, t, r, b: f32) -> Edges {
	return {l, t, r, b}
}

rad :: proc(v: f32) -> Radius {
	return {v, v, v, v}
}

rad4 :: proc(tl, tr, br, bl: f32) -> Radius {
	return {tl, tr, br, bl}
}

rect_contains :: proc(r: Rect, p: Vec2) -> bool {
	return p.x >= r.x && p.y >= r.y && p.x < r.x + r.w && p.y < r.y + r.h
}

rect_intersect :: proc(a, b: Rect) -> Rect {
	x0 := max(a.x, b.x)
	y0 := max(a.y, b.y)
	x1 := min(a.x + a.w, b.x + b.w)
	y1 := min(a.y + a.h, b.y + b.h)
	return {x0, y0, max(x1 - x0, 0), max(y1 - y0, 0)}
}
