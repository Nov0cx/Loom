package ui_dx11

import "core:math"
import win "core:sys/windows"
import d3d "vendor:directx/d3d11"
import ui "../../loom"

Batch :: struct {
	first:  u32,
	count:  u32,
	srv:    ^d3d.IShaderResourceView,
	clip:   ui.Rect,
	custom: ui.Cmd_Custom,
}

render :: proc(b: ^Backend, list: ui.Draw_List) {
	t := b.target
	if t == nil || t.hwnd == nil {
		return
	}

	cw, ch := client_size(t.hwnd)
	if cw <= 0 || ch <= 0 {
		return
	}

	b.dpi = window_dpi(b, t.hwnd)
	b.fb = {f32(cw), f32(ch)}
	b.scale = b.dpi
	b.view = {b.fb.x / b.scale, b.fb.y / b.scale}

	begin_batch(b)

	for cmd in list.cmds {
		switch v in cmd {
		case ui.Cmd_Rect:
			draw_rect(b, v)
		case ui.Cmd_Text:
			draw_text(b, v)
		case ui.Cmd_Image:
			draw_image(b, v)
		case ui.Cmd_Push_Clip:
			push_clip(b, v.rect)
		case ui.Cmd_Pop_Clip:
			pop_clip(b)
		case ui.Cmd_Custom:
			flush(b)
			append(&b.batches, Batch{clip = b.batch_clip, custom = v})
		}
	}
	flush(b)

	flush_atlas(b)
	submit(b, t)
}

@(private)
begin_batch :: proc(b: ^Backend) {
	clear(&b.verts)
	clear(&b.idxs)
	clear(&b.batches)
	clear(&b.clip)
	b.batch_first = 0
	b.batch_srv = b.white.srv
	b.batch_clip = {0, 0, b.view.x, b.view.y}
}

@(private)
flush :: proc(b: ^Backend) {
	n := u32(len(b.idxs))
	if n > b.batch_first {
		append(
			&b.batches,
			Batch {
				first = b.batch_first,
				count = n - b.batch_first,
				srv = b.batch_srv,
				clip = b.batch_clip,
			},
		)
	}
	b.batch_first = n
}

@(private)
apply_scissor :: proc(b: ^Backend, r: ui.Rect) {
	flush(b)
	b.batch_clip = r
}

@(private)
push_clip :: proc(b: ^Backend, r: ui.Rect) {
	next := r
	if len(b.clip) > 0 {
		next = ui.rect_intersect(b.clip[len(b.clip) - 1], r)
	}
	append(&b.clip, next)
	apply_scissor(b, next)
}

@(private)
pop_clip :: proc(b: ^Backend) {
	if len(b.clip) == 0 {
		return
	}
	pop(&b.clip)
	if len(b.clip) > 0 {
		apply_scissor(b, b.clip[len(b.clip) - 1])
	} else {
		apply_scissor(b, {0, 0, b.view.x, b.view.y})
	}
}

@(private)
use_texture :: proc(b: ^Backend, srv: ^d3d.IShaderResourceView) {
	if b.batch_srv == srv {
		return
	}
	flush(b)
	b.batch_srv = srv
}

@(private)
scissor_of :: proc(b: ^Backend, r: ui.Rect, t: ^Target) -> d3d.RECT {
	s := b.scale
	x0 := clamp(i32(math.round(r.x * s)), 0, i32(t.w))
	y0 := clamp(i32(math.round(r.y * s)), 0, i32(t.h))
	x1 := clamp(i32(math.round((r.x + r.w) * s)), x0, i32(t.w))
	y1 := clamp(i32(math.round((r.y + r.h) * s)), y0, i32(t.h))
	return {x0, y0, x1, y1}
}

@(private)
upload_geometry :: proc(b: ^Backend) -> bool {
	vb := len(b.verts) * size_of(Vertex)
	ib := len(b.idxs) * size_of(u32)
	if vb == 0 || ib == 0 {
		return false
	}
	if !grow_buffer(b, &b.vbuf, vb, {.VERTEX_BUFFER}) {
		return false
	}
	if !grow_buffer(b, &b.ibuf, ib, {.INDEX_BUFFER}) {
		return false
	}
	if !write_buffer(b, b.vbuf.buf, raw_data(b.verts), vb) {
		return false
	}
	return write_buffer(b, b.ibuf.buf, raw_data(b.idxs), ib)
}

@(private)
apply_state :: proc(b: ^Backend, t: ^Target) {
	rtv := t.rtv
	b.dctx->OMSetRenderTargets(1, &rtv, nil)

	vp := d3d.VIEWPORT {
		Width    = f32(t.w),
		Height   = f32(t.h),
		MaxDepth = 1,
	}
	b.dctx->RSSetViewports(1, &vp)

	b.dctx->IASetInputLayout(b.input)
	b.dctx->IASetPrimitiveTopology(.TRIANGLELIST)

	stride := u32(size_of(Vertex))
	offset := u32(0)
	vbuf := b.vbuf.buf
	b.dctx->IASetVertexBuffers(0, 1, &vbuf, &stride, &offset)
	b.dctx->IASetIndexBuffer(b.ibuf.buf, .R32_UINT, 0)

	b.dctx->VSSetShader(b.vs, nil, 0)
	cbuf := b.cbuf
	b.dctx->VSSetConstantBuffers(0, 1, &cbuf)

	b.dctx->PSSetShader(b.ps, nil, 0)
	smp := b.sampler
	b.dctx->PSSetSamplers(0, 1, &smp)

	blend_factor := [4]f32{0, 0, 0, 0}
	b.dctx->OMSetBlendState(b.blend, &blend_factor, 0xFFFFFFFF)
	b.dctx->OMSetDepthStencilState(b.depth, 0)
	b.dctx->RSSetState(b.raster)
}

@(private)
submit :: proc(b: ^Backend, t: ^Target) {
	if !ensure_target(b, t) {
		return
	}

	rtv := t.rtv
	b.dctx->OMSetRenderTargets(1, &rtv, nil)

	c := b.clear
	col := [4]f32{f32(c[0]) / 255, f32(c[1]) / 255, f32(c[2]) / 255, f32(c[3]) / 255}
	b.dctx->ClearRenderTargetView(t.rtv, &col)

	if upload_geometry(b) {
		u := Uniforms {
			size = b.view,
		}
		write_buffer(b, b.cbuf, &u, size_of(Uniforms))
		apply_state(b, t)

		last: ^d3d.IShaderResourceView
		for batch in b.batches {
			if batch.custom.draw != nil {
				batch.custom.draw(batch.custom.node, batch.custom.user)
				apply_state(b, t)
				last = nil
				continue
			}
			if batch.count == 0 {
				continue
			}

			sc := scissor_of(b, batch.clip, t)
			b.dctx->RSSetScissorRects(1, &sc)

			if batch.srv != last {
				srv := batch.srv
				b.dctx->PSSetShaderResources(0, 1, &srv)
				last = batch.srv
			}
			b.dctx->DrawIndexed(batch.count, batch.first, 0)
		}
	}

	sync := u32(b.opts.no_vsync ? 0 : 1)
	t.swap->Present(sync, {})
}

@(private)
vert :: proc(b: ^Backend, pos: ui.Vec2, uv: ui.Vec2, col: ui.Color) -> u32 {
	append(
		&b.verts,
		Vertex{pos = {pos.x, pos.y}, uv = {uv.x, uv.y}, col = {col[0], col[1], col[2], col[3]}},
	)
	return u32(len(b.verts) - 1)
}

@(private)
tri :: proc(b: ^Backend, a, c, d: u32) {
	append(&b.idxs, a, c, d)
}

@(private)
quad :: proc(b: ^Backend, r: ui.Rect, uv: ui.Rect, col: ui.Color) {
	if col[3] == 0 || r.w <= 0 || r.h <= 0 {
		return
	}
	i0 := vert(b, {r.x, r.y}, {uv.x, uv.y}, col)
	i1 := vert(b, {r.x + r.w, r.y}, {uv.x + uv.w, uv.y}, col)
	i2 := vert(b, {r.x + r.w, r.y + r.h}, {uv.x + uv.w, uv.y + uv.h}, col)
	i3 := vert(b, {r.x, r.y + r.h}, {uv.x, uv.y + uv.h}, col)
	tri(b, i0, i1, i2)
	tri(b, i0, i2, i3)
}

@(private)
arc_path :: proc(out: ^[dynamic]ui.Vec2, cx, cy, radius, a0, a1: f32, segs: int) {
	if radius <= 0 {
		append(out, ui.Vec2{cx, cy})
		return
	}
	for i in 0 ..= segs {
		a := a0 + (a1 - a0) * f32(i) / f32(segs)
		append(out, ui.Vec2{cx + math.cos(a) * radius, cy + math.sin(a) * radius})
	}
}

@(private)
rrect_path :: proc(b: ^Backend, out: ^[dynamic]ui.Vec2, r: ui.Rect, rad: ui.Radius) {
	clear(out)
	lim := min(r.w, r.h) * 0.5
	tl := clamp(rad.tl, 0, lim)
	tr := clamp(rad.tr, 0, lim)
	br := clamp(rad.br, 0, lim)
	bl := clamp(rad.bl, 0, lim)

	segs := b.opts.arc_segments
	PI :: math.PI
	arc_path(out, r.x + tl, r.y + tl, tl, PI, PI * 1.5, segs)
	arc_path(out, r.x + r.w - tr, r.y + tr, tr, PI * 1.5, PI * 2.0, segs)
	arc_path(out, r.x + r.w - br, r.y + r.h - br, br, 0, PI * 0.5, segs)
	arc_path(out, r.x + bl, r.y + r.h - bl, bl, PI * 0.5, PI, segs)
}

@(private)
paint_at :: proc(p: ui.Paint, x, y: f32, box: ui.Rect) -> ui.Color {
	switch v in p {
	case ui.Color:
		return v
	case ui.Gradient:
		if len(v.stops) == 0 {
			return {}
		}
		t: f32
		switch v.kind {
		case .Linear:
			dx, dy := math.cos(v.angle), math.sin(v.angle)
			cx, cy := box.x + box.w * 0.5, box.y + box.h * 0.5
			half := (abs(box.w * dx) + abs(box.h * dy)) * 0.5
			t = half > 0 ? (((x - cx) * dx + (y - cy) * dy) / half + 1) * 0.5 : 0
		case .Radial:
			cx, cy := box.x + box.w * 0.5, box.y + box.h * 0.5
			rr := max(box.w, box.h) * 0.5
			t = rr > 0 ? math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) / rr : 0
		}
		t = clamp(t, 0, 1)
		lo := v.stops[0]
		for s in v.stops {
			if s.t >= t {
				span := s.t - lo.t
				k := span > 0 ? (t - lo.t) / span : 0
				return mix_color(lo.color, s.color, k)
			}
			lo = s
		}
		return lo.color
	}
	return {}
}

@(private)
mix_color :: proc(a, c: ui.Color, k: f32) -> ui.Color {
	out: ui.Color
	for i in 0 ..< 4 {
		out[i] = u8(f32(a[i]) + (f32(c[i]) - f32(a[i])) * k + 0.5)
	}
	return out
}

@(private)
fill_poly :: proc(b: ^Backend, pts: []ui.Vec2, box: ui.Rect, p: ui.Paint) {
	if len(pts) < 3 || p == nil {
		return
	}
	use_texture(b, b.white.srv)

	cx, cy := box.x + box.w * 0.5, box.y + box.h * 0.5
	center := vert(b, {cx, cy}, {0.5, 0.5}, paint_at(p, cx, cy, box))
	first := vert(b, pts[0], {0.5, 0.5}, paint_at(p, pts[0].x, pts[0].y, box))
	prev := first
	for i in 1 ..< len(pts) {
		cur := vert(b, pts[i], {0.5, 0.5}, paint_at(p, pts[i].x, pts[i].y, box))
		tri(b, center, prev, cur)
		prev = cur
	}
	tri(b, center, prev, first)
}

@(private)
stroke_ring :: proc(b: ^Backend, outer, inner: []ui.Vec2, col: ui.Color) {
	n := min(len(outer), len(inner))
	if n < 3 || col[3] == 0 {
		return
	}
	use_texture(b, b.white.srv)

	for i in 0 ..< n {
		j := (i + 1) % n
		o0 := vert(b, outer[i], {0.5, 0.5}, col)
		n0 := vert(b, inner[i], {0.5, 0.5}, col)
		n1 := vert(b, inner[j], {0.5, 0.5}, col)
		o1 := vert(b, outer[j], {0.5, 0.5}, col)
		tri(b, o0, n0, n1)
		tri(b, o0, n1, o1)
	}
}

@(private)
inset_radius :: proc(rad: ui.Radius, w: f32) -> ui.Radius {
	return {max(rad.tl - w, 0), max(rad.tr - w, 0), max(rad.br - w, 0), max(rad.bl - w, 0)}
}

@(private)
grow_radius :: proc(rad: ui.Radius, w: f32) -> ui.Radius {
	return {rad.tl + w, rad.tr + w, rad.br + w, rad.bl + w}
}

@(private)
shadow_alpha :: proc(base: u8, steps: int, t: f32) -> ui.Color {
	return {0, 0, 0, u8(f32(base) / f32(steps) * (1 - t))}
}

draw_rect :: proc(b: ^Backend, cmd: ui.Cmd_Rect) {
	box := cmd.rect
	s := cmd.shadow

	if s.color[3] > 0 && !s.inset {
		steps := int(clamp(s.blur * 0.5, 1, MAX_SHADOW_STEPS))
		for i in 0 ..< steps {
			t := f32(i) / f32(steps)
			grow := s.spread + s.blur * t
			a := shadow_alpha(s.color[3], steps, t)
			r := ui.Rect {
				box.x + s.offset.x - grow,
				box.y + s.offset.y - grow,
				box.w + grow * 2,
				box.h + grow * 2,
			}
			rrect_path(b, &b.path_a, r, grow_radius(cmd.radius, grow))
			fill_poly(b, b.path_a[:], r, ui.Color{s.color[0], s.color[1], s.color[2], a[3]})
		}
	}

	rrect_path(b, &b.path_a, box, cmd.radius)
	fill_poly(b, b.path_a[:], box, cmd.paint)

	if s.color[3] > 0 && s.inset {
		steps := int(clamp(s.blur * 0.5, 1, MAX_SHADOW_STEPS))
		for i in 0 ..< steps {
			t := f32(i) / f32(steps)
			shrink := s.spread + s.blur * t
			a := shadow_alpha(s.color[3], steps, t)
			r := ui.Rect {
				box.x + s.offset.x + shrink,
				box.y + s.offset.y + shrink,
				box.w - shrink * 2,
				box.h - shrink * 2,
			}
			if r.w <= 0 || r.h <= 0 {
				break
			}
			rrect_path(b, &b.path_a, box, cmd.radius)
			rrect_path(b, &b.path_b, r, inset_radius(cmd.radius, shrink))
			stroke_ring(
				b,
				b.path_a[:],
				b.path_b[:],
				ui.Color{s.color[0], s.color[1], s.color[2], a[3]},
			)
		}
	}

	if cmd.border.color[3] == 0 {
		return
	}

	bw := cmd.border.width
	if bw.l == bw.t && bw.t == bw.r && bw.r == bw.b {
		if bw.l > 0 {
			w := bw.l
			inner := ui.Rect{box.x + w, box.y + w, max(box.w - w * 2, 0), max(box.h - w * 2, 0)}
			rrect_path(b, &b.path_a, box, cmd.radius)
			rrect_path(b, &b.path_b, inner, inset_radius(cmd.radius, w))
			stroke_ring(b, b.path_a[:], b.path_b[:], cmd.border.color)
		}
		return
	}

	col := cmd.border.color
	if bw.t > 0 {
		fill_box(b, {box.x, box.y, box.w, bw.t}, col)
	}
	if bw.b > 0 {
		fill_box(b, {box.x, box.y + box.h - bw.b, box.w, bw.b}, col)
	}
	if bw.l > 0 {
		fill_box(b, {box.x, box.y, bw.l, box.h}, col)
	}
	if bw.r > 0 {
		fill_box(b, {box.x + box.w - bw.r, box.y, bw.r, box.h}, col)
	}
}

@(private)
fill_box :: proc(b: ^Backend, r: ui.Rect, col: ui.Color) {
	use_texture(b, b.white.srv)
	quad(b, r, {0.5, 0.5, 0, 0}, col)
}

draw_text :: proc(b: ^Backend, cmd: ui.Cmd_Text) {
	if cmd.text == "" || cmd.color[3] == 0 || cmd.size <= 0 {
		return
	}

	f, _ := face_of(b, cmd.font)
	px := atlas_px(b, cmd.size)
	sc := cmd.size / f32(px)
	track := tracking_of(f, cmd.size, cmd.spacing)

	pen := cmd.pos.x
	for r in cmd.text {
		g := glyph_of(b, cmd.font, px, r)
		if g.drawable {
			use_texture(b, b.pages[g.page].srv)
			gx := math.round((pen + g.x0 * sc) * b.scale) / b.scale
			gy := math.round((cmd.pos.y + g.y0 * sc) * b.scale) / b.scale
			quad(b, {gx, gy, g.w * sc, g.h * sc}, {g.u0, g.v0, g.u1 - g.u0, g.v1 - g.v0}, cmd.color)
		}
		pen += advance_of(f, cmd.size, r) + track
	}
}

draw_image :: proc(b: ^Backend, cmd: ui.Cmd_Image) {
	info, ok := b.textures[u32(cmd.tex)]
	if !ok || cmd.rect.w <= 0 || cmd.rect.h <= 0 {
		return
	}

	uv := cmd.uv
	if uv.w == 0 || uv.h == 0 {
		uv = {0, 0, 1, 1}
	}
	tint := cmd.tint
	if tint == (ui.Color{}) {
		tint = {255, 255, 255, 255}
	}

	use_texture(b, info.srv)
	quad(b, cmd.rect, uv, tint)
}

@(private)
time_now :: proc() -> f64 {
	freq, counter: win.LARGE_INTEGER
	win.QueryPerformanceFrequency(&freq)
	win.QueryPerformanceCounter(&counter)
	if freq == 0 {
		return 0
	}
	return f64(counter) / f64(freq)
}
