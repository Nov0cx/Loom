package ui_sokol

import "core:c"
import "core:math"
import sapp "../../third_party/sokol/sokol/app"
import sglue "../../third_party/sokol/sokol/glue"
import sg "../../third_party/sokol/sokol/gfx"
import ui "../../loom"

Batch :: struct {
	first:  u32,
	count:  u32,
	view:   sg.View,
	clip:   ui.Rect,
	custom: ui.Cmd_Custom,
}

render :: proc(b: ^Backend, list: ui.Draw_List) {
	fw := sapp.widthf()
	fh := sapp.heightf()
	if fw <= 0 || fh <= 0 {
		return
	}

	b.dpi = backend_dpi(b)
	b.scale = b.dpi
	b.fb = {fw, fh}
	b.view = {fw / b.scale, fh / b.scale}

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

	grow_buffers(b)
	flush_atlas(b)
	submit(b)
}

@(private)
begin_batch :: proc(b: ^Backend) {
	clear(&b.verts)
	clear(&b.idxs)
	clear(&b.batches)
	clear(&b.clip)
	b.batch_first = 0
	b.batch_view = b.white.view
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
				view = b.batch_view,
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
use_texture :: proc(b: ^Backend, view: sg.View) {
	if b.batch_view == view {
		return
	}
	flush(b)
	b.batch_view = view
}

@(private)
scissor_of :: proc(b: ^Backend, r: ui.Rect) -> (x, y, w, h: i32) {
	s := b.scale
	x0 := clamp(i32(math.round(r.x * s)), 0, i32(b.fb.x))
	y0 := clamp(i32(math.round(r.y * s)), 0, i32(b.fb.y))
	x1 := clamp(i32(math.round((r.x + r.w) * s)), x0, i32(b.fb.x))
	y1 := clamp(i32(math.round((r.y + r.h) * s)), y0, i32(b.fb.y))
	return x0, y0, x1 - x0, y1 - y0
}

@(private)
grow_buffers :: proc(b: ^Backend) {
	if b.want_v > b.vcap {
		sg.destroy_buffer(b.vbuf)
		b.vcap = max(b.want_v, b.vcap * 2)
		b.vbuf = sg.make_buffer(
			{
				usage = {vertex_buffer = true, dynamic_update = true},
				size = c.size_t(b.vcap * size_of(Vertex)),
			},
		)
	}
	if b.want_i > b.icap {
		sg.destroy_buffer(b.ibuf)
		b.icap = max(b.want_i, b.icap * 2)
		b.ibuf = sg.make_buffer(
			{
				usage = {index_buffer = true, dynamic_update = true},
				size = c.size_t(b.icap * size_of(u32)),
			},
		)
	}
	b.want_v = len(b.verts)
	b.want_i = len(b.idxs)
}

@(private)
submit :: proc(b: ^Backend) {
	col := b.clear
	pass := sg.Pass {
		swapchain = swapchain_of(b),
	}
	pass.action.colors[0] = {
		load_action = .CLEAR,
		clear_value = {
			f32(col[0]) / 255,
			f32(col[1]) / 255,
			f32(col[2]) / 255,
			f32(col[3]) / 255,
		},
	}

	n_verts := min(len(b.verts), b.vcap)
	n_idxs := min(len(b.idxs), b.icap)
	has_geometry := n_verts > 0 && n_idxs > 0

	if has_geometry {
		sg.update_buffer(
			b.vbuf,
			{ptr = raw_data(b.verts), size = c.size_t(n_verts * size_of(Vertex))},
		)
		sg.update_buffer(b.ibuf, {ptr = raw_data(b.idxs), size = c.size_t(n_idxs * size_of(u32))})
	}

	sg.begin_pass(pass)

	if has_geometry {
		sg.apply_pipeline(b.pip)

		u := Uniforms {
			size = b.view,
		}
		sg.apply_uniforms(0, {ptr = &u, size = size_of(Uniforms)})

		bind := sg.Bindings{}
		bind.vertex_buffers[0] = b.vbuf
		bind.index_buffer = b.ibuf
		bind.samplers[0] = b.smp

		last: sg.View
		for batch in b.batches {
			if batch.custom.draw != nil {
				batch.custom.draw(batch.custom.node, batch.custom.user)
				sg.apply_pipeline(b.pip)
				sg.apply_uniforms(0, {ptr = &u, size = size_of(Uniforms)})
				last = {}
				continue
			}
			if batch.count == 0 || int(batch.first + batch.count) > n_idxs {
				continue
			}

			x, y, w, h := scissor_of(b, batch.clip)
			sg.apply_scissor_rect(x, y, w, h, true)

			if batch.view != last {
				bind.views[0] = batch.view
				sg.apply_bindings(bind)
				last = batch.view
			}
			sg.draw(batch.first, batch.count, 1)
		}
	}

	sg.end_pass()
	sg.commit()
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
	use_texture(b, b.white.view)

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
	use_texture(b, b.white.view)

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
	use_texture(b, b.white.view)
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
			use_texture(b, b.pages[g.page].view)
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

	use_texture(b, info.view)
	quad(b, cmd.rect, uv, tint)
}

@(private)
swapchain_of :: proc(b: ^Backend) -> sg.Swapchain {
	return sglue.swapchain()
}
