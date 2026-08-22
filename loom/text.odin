package loom

import "core:math"

@(private)
measure_text_node :: proc(ctx: ^Context, n: ^Node, max_w: f32) -> Vec2 {
	if n.el.text == "" {
		return {}
	}
	mt := ctx.cfg.backend.measure_text
	if mt == nil {
		return {}
	}

	p := &n.computed
	out := mt(p.font, p.font_size, n.el.text, max(max_w, 0), ctx.cfg.backend.user)

	if p.line_height > 0 {
		def := text_line_height(ctx, p)
		if def > 0 {
			lines := math.round(out.y / def)
			out.y = max(lines, 1) * p.line_height * p.font_size
		}
	}
	return out
}

@(private)
text_metrics :: proc(ctx: ^Context, p: ^Props) -> Font_Metrics {
	fm := ctx.cfg.backend.font_metrics
	if fm == nil {
		return {}
	}
	return fm(p.font, p.font_size, ctx.cfg.backend.user)
}

@(private)
text_line_height :: proc(ctx: ^Context, p: ^Props) -> f32 {
	m := text_metrics(ctx, p)
	return m.ascent - m.descent + m.line_gap
}

@(private)
text_ascent :: proc(ctx: ^Context, p: ^Props) -> f32 {
	return text_metrics(ctx, p).ascent
}
