package loom

import "base:runtime"
import "core:fmt"

Font_Metrics :: struct {
	ascent, descent, line_gap: f32,
}

Viewport_Handle :: distinct u64

Viewport_Events :: struct {
	mouse:          Vec2,
	wheel:          Vec2,
	mouse_down:     Mouse_Set,
	mouse_pressed:  Mouse_Set,
	mouse_released: Mouse_Set,
	keys_down:      Key_Set,
	keys_pressed:   Key_Set,
	mods:           Mod_Set,
	text:           string,
	rect:           Rect,
	focused:        bool,
	has_mouse:      bool,
	closed:         bool,
}

Viewport_Ops :: struct {
	create:   proc(title: string, rect: Rect, user: rawptr) -> Viewport_Handle,
	destroy:  proc(v: Viewport_Handle, user: rawptr),
	set_rect: proc(v: Viewport_Handle, rect: Rect, user: rawptr),
	begin:    proc(v: Viewport_Handle, user: rawptr),
	end:      proc(v: Viewport_Handle, user: rawptr),
	poll:     proc(v: Viewport_Handle, user: rawptr) -> Viewport_Events,
}

Backend :: struct {
	measure_run:   proc(font: Font, size: f32, text: string, spacing: f32, user: rawptr) -> f32,
	font_metrics:  proc(font: Font, size: f32, user: rawptr) -> Font_Metrics,
	// Optional. A host with a shaped-run cache answers a caret query more
	// cheaply, and more correctly across a ligature, than a prefix re-measure.
	// Loom falls back to prefix measurement when either is nil.
	offset_x:      proc(
		font: Font,
		size: f32,
		text: string,
		spacing, tab_origin: f32,
		at: int,
		user: rawptr,
	) -> f32,
	index_at:      proc(
		font: Font,
		size: f32,
		text: string,
		spacing, tab_origin, x: f32,
		user: rawptr,
	) -> int,
	set_cursor:    proc(c: Cursor, user: rawptr),
	clipboard_get: proc(user: rawptr) -> string,
	clipboard_set: proc(text: string, user: rawptr),
	user:          rawptr,
	viewports:     Maybe(Viewport_Ops),
}

has_viewports :: proc() -> bool {
	return viewport_ops(ctx_of()) != nil
}

@(private)
viewport_ops :: proc(ctx: ^Context) -> ^Viewport_Ops {
	ops, ok := &ctx.cfg.backend.viewports.(Viewport_Ops)
	if !ok {
		return nil
	}
	if ops.create == nil || ops.destroy == nil || ops.poll == nil {
		return nil
	}
	return ops
}

Config :: struct {
	backend:           Backend,
	root:              Props,
	theme:             Theme,
	settings_rate:     f32,
	prune_after:       u32,
	text_cache_frames: u32,
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
		measure_run = proc(font: Font, size: f32, text: string, spacing: f32, user: rawptr) -> f32 {
			return 0
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

@(private)
check_backend :: proc(b: Backend, loc := #caller_location) {
	missing := ""
	switch {
	case b.measure_run == nil:
		missing = "measure_run"
	case b.font_metrics == nil:
		missing = "font_metrics"
	case b.set_cursor == nil:
		missing = "set_cursor"
	case b.clipboard_get == nil:
		missing = "clipboard_get"
	case b.clipboard_set == nil:
		missing = "clipboard_set"
	}
	if missing != "" {
		panic(fmt.tprintf("loom: Config.backend.%s is nil", missing), loc)
	}
}
