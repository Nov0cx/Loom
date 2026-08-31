package ui_vulkan_1_3

import "core:math"
import "core:mem"
import vk "vendor:vulkan"
import "vendor:glfw"
import ui "../../loom"

Batch :: struct {
	first:  u32,
	count:  u32,
	set:    vk.DescriptorSet,
	clip:   ui.Rect,
	custom: ui.Cmd_Custom,
}

render :: proc(b: ^Backend, list: ui.Draw_List) {
	t := b.target
	if t == nil {
		return
	}

	ww, wh := glfw.GetWindowSize(t.win)
	fw, fh := glfw.GetFramebufferSize(t.win)
	if ww <= 0 || wh <= 0 || fw <= 0 || fh <= 0 {
		return
	}

	b.view = {f32(ww), f32(wh)}
	b.fb = {f32(fw), f32(fh)}
	b.scale = f32(fw) / f32(ww)

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
	b.batch_set = b.white.set
	b.batch_clip = {0, 0, b.view.x, b.view.y}
}

@(private)
flush :: proc(b: ^Backend) {
	n := u32(len(b.idxs))
	if n > b.batch_first {
		append(
			&b.batches,
			Batch{first = b.batch_first, count = n - b.batch_first, set = b.batch_set, clip = b.batch_clip},
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
use_texture :: proc(b: ^Backend, set: vk.DescriptorSet) {
	if b.batch_set == set {
		return
	}
	flush(b)
	b.batch_set = set
}

@(private)
scissor_of :: proc(b: ^Backend, r: ui.Rect, ext: vk.Extent2D) -> vk.Rect2D {
	s := b.scale
	x0 := clamp(i32(math.round(r.x * s)), 0, i32(ext.width))
	y0 := clamp(i32(math.round(r.y * s)), 0, i32(ext.height))
	x1 := clamp(i32(math.round((r.x + r.w) * s)), x0, i32(ext.width))
	y1 := clamp(i32(math.round((r.y + r.h) * s)), y0, i32(ext.height))
	return {offset = {x0, y0}, extent = {u32(x1 - x0), u32(y1 - y0)}}
}

@(private)
upload_geometry :: proc(b: ^Backend, f: ^Frame) -> bool {
	vb := vk.DeviceSize(len(b.verts) * size_of(Vertex))
	ib := vk.DeviceSize(len(b.idxs) * size_of(u32))
	if vb == 0 || ib == 0 {
		return false
	}
	if !grow_buffer(b, &f.vbuf, vb, {.VERTEX_BUFFER}) {
		return false
	}
	if !grow_buffer(b, &f.ibuf, ib, {.INDEX_BUFFER}) {
		return false
	}
	mem.copy(f.vbuf.ptr, raw_data(b.verts), int(vb))
	mem.copy(f.ibuf.ptr, raw_data(b.idxs), int(ib))
	return true
}

@(private)
submit :: proc(b: ^Backend, t: ^Target) {
	if !ensure_target(b, t) {
		return
	}

	f := &t.frames[t.frame]
	vk.WaitForFences(b.device, 1, &f.fence, true, max(u64))

	image: u32
	if !acquire(b, t, f, &image) {
		return
	}
	vk.ResetFences(b.device, 1, &f.fence)

	has_geometry := upload_geometry(b, f)

	vk.ResetCommandBuffer(f.cmd, {})
	bi := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	vk.BeginCommandBuffer(f.cmd, &bi)

	begin_pass(b, t, f, image)

	if has_geometry {
		vp := vk.Viewport {
			width    = f32(t.extent.width),
			height   = f32(t.extent.height),
			maxDepth = 1,
		}
		vk.CmdSetViewport(f.cmd, 0, 1, &vp)
		vk.CmdBindPipeline(f.cmd, .GRAPHICS, b.pipeline)

		off := vk.DeviceSize(0)
		vk.CmdBindVertexBuffers(f.cmd, 0, 1, &f.vbuf.buf, &off)
		vk.CmdBindIndexBuffer(f.cmd, f.ibuf.buf, 0, .UINT32)

		push := Push {
			size = b.view,
		}
		vk.CmdPushConstants(f.cmd, b.layout, {.VERTEX}, 0, size_of(Push), &push)

		last := vk.DescriptorSet(0)
		for batch in b.batches {
			if batch.custom.draw != nil {
				batch.custom.draw(batch.custom.node, batch.custom.user)
				continue
			}
			if batch.count == 0 {
				continue
			}

			sc := scissor_of(b, batch.clip, t.extent)
			vk.CmdSetScissor(f.cmd, 0, 1, &sc)

			if batch.set != last {
				set := batch.set
				vk.CmdBindDescriptorSets(f.cmd, .GRAPHICS, b.layout, 0, 1, &set, 0, nil)
				last = batch.set
			}
			vk.CmdDrawIndexed(f.cmd, batch.count, 1, batch.first, 0, 0)
		}
	}

	end_pass(b, t, f, image)
	vk.EndCommandBuffer(f.cmd)

	wait := vk.SemaphoreSubmitInfo {
		sType     = .SEMAPHORE_SUBMIT_INFO,
		semaphore = f.acquire,
		stageMask = {.COLOR_ATTACHMENT_OUTPUT},
	}
	signal := vk.SemaphoreSubmitInfo {
		sType     = .SEMAPHORE_SUBMIT_INFO,
		semaphore = t.release[image],
		stageMask = {.COLOR_ATTACHMENT_OUTPUT},
	}
	cb := vk.CommandBufferSubmitInfo {
		sType         = .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer = f.cmd,
	}
	si := vk.SubmitInfo2 {
		sType                    = .SUBMIT_INFO_2,
		waitSemaphoreInfoCount   = 1,
		pWaitSemaphoreInfos      = &wait,
		commandBufferInfoCount   = 1,
		pCommandBufferInfos      = &cb,
		signalSemaphoreInfoCount = 1,
		pSignalSemaphoreInfos    = &signal,
	}
	vk.QueueSubmit2(b.queue, 1, &si, f.fence)

	present(b, t, image)
	t.frame = (t.frame + 1) % FRAMES_IN_FLIGHT
}

@(private)
clear_value :: proc(b: ^Backend) -> vk.ClearValue {
	c := b.clear
	return {
		color = {
			float32 = {f32(c[0]) / 255, f32(c[1]) / 255, f32(c[2]) / 255, f32(c[3]) / 255},
		},
	}
}

@(private)
begin_pass :: proc(b: ^Backend, t: ^Target, f: ^Frame, image: u32) {
	ms := b.samples != {._1}

	barrier(
		f.cmd,
		t.images[image],
		.UNDEFINED,
		.COLOR_ATTACHMENT_OPTIMAL,
		{.TOP_OF_PIPE},
		{},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_WRITE},
	)
	if ms {
		barrier(
			f.cmd,
			t.ms.img,
			.UNDEFINED,
			.COLOR_ATTACHMENT_OPTIMAL,
			{.TOP_OF_PIPE},
			{},
			{.COLOR_ATTACHMENT_OUTPUT},
			{.COLOR_ATTACHMENT_WRITE},
		)
	}

	att := vk.RenderingAttachmentInfo {
		sType              = .RENDERING_ATTACHMENT_INFO,
		imageView          = ms ? t.ms.view : t.views[image],
		imageLayout        = .COLOR_ATTACHMENT_OPTIMAL,
		resolveMode        = ms ? {.AVERAGE} : {},
		resolveImageView   = ms ? t.views[image] : 0,
		resolveImageLayout = ms ? .COLOR_ATTACHMENT_OPTIMAL : .UNDEFINED,
		loadOp             = .CLEAR,
		storeOp            = .STORE,
		clearValue         = clear_value(b),
	}
	ri := vk.RenderingInfo {
		sType                = .RENDERING_INFO,
		renderArea           = {extent = t.extent},
		layerCount           = 1,
		colorAttachmentCount = 1,
		pColorAttachments    = &att,
	}
	vk.CmdBeginRendering(f.cmd, &ri)
}

@(private)
end_pass :: proc(b: ^Backend, t: ^Target, f: ^Frame, image: u32) {
	vk.CmdEndRendering(f.cmd)
	barrier(
		f.cmd,
		t.images[image],
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_WRITE},
		{.BOTTOM_OF_PIPE},
		{},
	)
}

@(private)
barrier :: proc(
	cmd: vk.CommandBuffer,
	img: vk.Image,
	from, to: vk.ImageLayout,
	src_stage: vk.PipelineStageFlags2,
	src_access: vk.AccessFlags2,
	dst_stage: vk.PipelineStageFlags2,
	dst_access: vk.AccessFlags2,
) {
	bar := vk.ImageMemoryBarrier2 {
		sType               = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask        = src_stage,
		srcAccessMask       = src_access,
		dstStageMask        = dst_stage,
		dstAccessMask       = dst_access,
		oldLayout           = from,
		newLayout           = to,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image               = img,
		subresourceRange    = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	di := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &bar,
	}
	vk.CmdPipelineBarrier2(cmd, &di)
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
	use_texture(b, b.white.set)

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
	use_texture(b, b.white.set)

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
	use_texture(b, b.white.set)
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
			use_texture(b, b.pages[g.page].img.set)
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

	use_texture(b, info.set)
	quad(b, cmd.rect, uv, tint)
}
