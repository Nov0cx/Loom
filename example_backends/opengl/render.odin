package ui_opengl

import "core:math"
import gl "vendor:OpenGL"
import "vendor:glfw"
import ui "../../loom"

render :: proc(b: ^Backend, list: ui.Draw_List) {
	win := b.target != nil ? b.target : b.win
	ww, wh := glfw.GetWindowSize(win)
	fw, fh := glfw.GetFramebufferSize(win)
	if ww <= 0 || wh <= 0 || fw <= 0 || fh <= 0 {
		return
	}

	b.view = {f32(ww), f32(wh)}
	b.fb = {f32(fw), f32(fh)}
	b.scale = f32(fw) / f32(ww)

	begin_gl(b, win)
	clear(&b.clip)
	apply_scissor(b, {0, 0, b.view.x, b.view.y})

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
			v.draw(v.node, v.user)
			begin_gl(b, win)
		}
	}

	flush(b)
	end_gl(b)
}

@(private)
begin_gl :: proc(b: ^Backend, win: glfw.WindowHandle) {
	w := win_state(b, win)
	if w.vao == 0 {
		w.vao = make_vao(b)
	}

	gl.Viewport(0, 0, i32(b.fb.x), i32(b.fb.y))
	gl.Disable(gl.DEPTH_TEST)
	gl.Disable(gl.CULL_FACE)
	gl.Enable(gl.BLEND)
	gl.BlendEquation(gl.FUNC_ADD)
	gl.BlendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
	gl.Enable(gl.SCISSOR_TEST)
	gl.UseProgram(b.prog)
	gl.Uniform2f(b.u_size, b.view.x, b.view.y)
	gl.Uniform1i(b.u_tex, 0)
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindVertexArray(w.vao)
	b.batch_tex = 0
}

@(private)
end_gl :: proc(b: ^Backend) {
	gl.BindVertexArray(0)
	gl.Disable(gl.SCISSOR_TEST)
	gl.BindTexture(gl.TEXTURE_2D, 0)
	gl.UseProgram(0)
}

@(private)
apply_scissor :: proc(b: ^Backend, r: ui.Rect) {
	s := b.scale
	x := i32(math.round(r.x * s))
	y := i32(math.round(b.fb.y - (r.y + r.h) * s))
	w := i32(math.round(r.w * s))
	h := i32(math.round(r.h * s))
	gl.Scissor(x, y, max(w, 0), max(h, 0))
}

@(private)
push_clip :: proc(b: ^Backend, r: ui.Rect) {
	next := r
	if len(b.clip) > 0 {
		next = ui.rect_intersect(b.clip[len(b.clip) - 1], r)
	}
	append(&b.clip, next)
	flush(b)
	apply_scissor(b, next)
}

@(private)
pop_clip :: proc(b: ^Backend) {
	if len(b.clip) == 0 {
		return
	}
	pop(&b.clip)
	flush(b)
	if len(b.clip) > 0 {
		apply_scissor(b, b.clip[len(b.clip) - 1])
	} else {
		apply_scissor(b, {0, 0, b.view.x, b.view.y})
	}
}

@(private)
use_texture :: proc(b: ^Backend, tex: u32) {
	if b.batch_tex == tex {
		return
	}
	flush(b)
	b.batch_tex = tex
}

@(private)
flush :: proc(b: ^Backend) {
	if len(b.idxs) == 0 {
		clear(&b.verts)
		return
	}

	gl.BindTexture(gl.TEXTURE_2D, b.batch_tex != 0 ? b.batch_tex : b.white)
	gl.BindBuffer(gl.ARRAY_BUFFER, b.vbo)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(b.verts) * size_of(Vertex),
		raw_data(b.verts),
		gl.STREAM_DRAW,
	)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, b.ibo)
	gl.BufferData(
		gl.ELEMENT_ARRAY_BUFFER,
		len(b.idxs) * size_of(u32),
		raw_data(b.idxs),
		gl.STREAM_DRAW,
	)
	gl.DrawElements(gl.TRIANGLES, i32(len(b.idxs)), gl.UNSIGNED_INT, nil)

	clear(&b.verts)
	clear(&b.idxs)
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
	use_texture(b, b.white)

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
	use_texture(b, b.white)

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
	use_texture(b, b.white)
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
			use_texture(b, b.pages[g.page].tex)
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

	use_texture(b, info.id)
	quad(b, cmd.rect, uv, tint)
}
