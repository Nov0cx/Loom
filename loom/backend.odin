package loom

import "base:runtime"

Font_Metrics :: struct {
	ascent, descent, line_gap: f32,
}

Backend :: struct {
	measure_text:  proc(font: Font, size: f32, text: string, max_w: f32, user: rawptr) -> Vec2,
	font_metrics:  proc(font: Font, size: f32, user: rawptr) -> Font_Metrics,
	set_cursor:    proc(c: Cursor, user: rawptr),
	clipboard_get: proc(user: rawptr) -> string,
	clipboard_set: proc(text: string, user: rawptr),
	user:          rawptr,
}

Config :: struct {
	backend:           Backend,
	root:              Props,
	prune_after:       u32,
	double_click:      f32,
	scroll_speed:      f32,
	scroll_inertia:    f32,
	scroll_damping:    f32,
	scroll_to_dur:     f32,
	no_scroll_inertia: bool,
	frame_allocator:   runtime.Allocator,
}

noop_backend :: proc() -> Backend {
	return Backend {
		measure_text = proc(font: Font, size: f32, text: string, max_w: f32, user: rawptr) -> Vec2 {
			return {}
		},
		font_metrics = proc(font: Font, size: f32, user: rawptr) -> Font_Metrics {
			return {}
		},
		set_cursor = proc(c: Cursor, user: rawptr) {},
		clipboard_get = proc(user: rawptr) -> string {
			return ""
		},
		clipboard_set = proc(text: string, user: rawptr) {},
	}
}
