package loom

import "core:slice"
import "core:strings"

Theme :: struct {
	name:            string,
	dark:            bool,
	bg:              Color,
	surface:         Color,
	raised:          Color,
	overlay:         Color,
	border:          Color,
	divider:         Color,
	text:            Color,
	text_muted:      Color,
	text_faint:      Color,
	accent:          Color,
	accent_hover:    Color,
	accent_text:     Color,
	selection:       Color,
	success:         Color,
	warning:         Color,
	danger:          Color,
	info:            Color,
	scrollbar:       Color,
	scrollbar_hover: Color,
	shadow:          Color,
}

LOOM_DARK :: Theme {
	name            = "loom_dark",
	dark            = true,
	bg              = {16, 18, 25, 255},
	surface         = {22, 26, 36, 255},
	raised          = {31, 36, 49, 255},
	overlay         = {41, 48, 63, 255},
	border          = {46, 53, 70, 255},
	divider         = {33, 39, 54, 255},
	text            = {221, 225, 236, 255},
	text_muted      = {144, 153, 176, 255},
	text_faint      = {98, 107, 129, 255},
	accent          = {110, 114, 240, 255},
	accent_hover    = {133, 136, 245, 255},
	accent_text     = {244, 245, 255, 255},
	selection       = {43, 47, 85, 255},
	success         = {79, 191, 139, 255},
	warning         = {224, 165, 74, 255},
	danger          = {229, 99, 107, 255},
	info            = {79, 163, 217, 255},
	scrollbar       = {58, 66, 86, 255},
	scrollbar_hover = {76, 86, 112, 255},
	shadow          = {0, 0, 0, 153},
}

LOOM_LIGHT :: Theme {
	name            = "loom_light",
	dark            = false,
	bg              = {247, 248, 251, 255},
	surface         = {255, 255, 255, 255},
	raised          = {238, 240, 246, 255},
	overlay         = {227, 230, 239, 255},
	border          = {213, 218, 229, 255},
	divider         = {230, 233, 241, 255},
	text            = {26, 30, 42, 255},
	text_muted      = {89, 98, 118, 255},
	text_faint      = {139, 147, 165, 255},
	accent          = {84, 87, 229, 255},
	accent_hover    = {66, 69, 208, 255},
	accent_text     = {255, 255, 255, 255},
	selection       = {220, 222, 251, 255},
	success         = {46, 158, 107, 255},
	warning         = {184, 122, 23, 255},
	danger          = {206, 59, 69, 255},
	info            = {42, 127, 191, 255},
	scrollbar       = {196, 202, 215, 255},
	scrollbar_hover = {167, 175, 193, 255},
	shadow          = {26, 30, 42, 38},
}

DEFAULT_THEME :: LOOM_DARK

@(rodata)
BUILTIN_THEMES := [?]Theme{LOOM_DARK, LOOM_LIGHT}

Theme_Slot :: struct {
	name:   string,
	offset: uintptr,
}

@(rodata)
THEME_SLOTS := [?]Theme_Slot {
	{"bg", offset_of(Theme, bg)},
	{"surface", offset_of(Theme, surface)},
	{"raised", offset_of(Theme, raised)},
	{"overlay", offset_of(Theme, overlay)},
	{"border", offset_of(Theme, border)},
	{"divider", offset_of(Theme, divider)},
	{"text", offset_of(Theme, text)},
	{"text_muted", offset_of(Theme, text_muted)},
	{"text_faint", offset_of(Theme, text_faint)},
	{"accent", offset_of(Theme, accent)},
	{"accent_hover", offset_of(Theme, accent_hover)},
	{"accent_text", offset_of(Theme, accent_text)},
	{"selection", offset_of(Theme, selection)},
	{"success", offset_of(Theme, success)},
	{"warning", offset_of(Theme, warning)},
	{"danger", offset_of(Theme, danger)},
	{"info", offset_of(Theme, info)},
	{"scrollbar", offset_of(Theme, scrollbar)},
	{"scrollbar_hover", offset_of(Theme, scrollbar_hover)},
	{"shadow", offset_of(Theme, shadow)},
}

theme_slot :: proc(t: ^Theme, name: string) -> ^Color {
	for s in THEME_SLOTS {
		if s.name == name {
			return (^Color)(uintptr(t) + s.offset)
		}
	}
	return nil
}

theme :: proc() -> ^Theme {
	return &ctx_of().theme
}

theme_of :: proc(ctx: ^Context) -> ^Theme {
	return &ctx.theme
}

set_theme :: proc(t: Theme) {
	ctx := ctx_of()
	if ctx.theme == t {
		return
	}
	if known, ok := theme_by_name_ctx(ctx, t.name); !ok || known != t {
		if t.name != "" {
			register_theme_ctx(ctx, t)
		}
	}
	ctx.theme = t
	mark_dirty(ctx)
}

set_theme_name :: proc(name: string) -> bool {
	ctx := ctx_of()
	t, ok := theme_by_name_ctx(ctx, name)
	if !ok {
		return false
	}
	set_theme(t)
	return true
}

theme_by_name :: proc(name: string) -> (Theme, bool) {
	return theme_by_name_ctx(ctx_of(), name)
}

@(private)
theme_by_name_ctx :: proc(ctx: ^Context, name: string) -> (Theme, bool) {
	if t, ok := ctx.themes[name]; ok {
		return t, true
	}
	for t in BUILTIN_THEMES {
		if t.name == name {
			return t, true
		}
	}
	return {}, false
}

register_theme :: proc(t: Theme) {
	register_theme_ctx(ctx_of(), t)
}

@(private)
register_theme_ctx :: proc(ctx: ^Context, t: Theme) {
	assert(t.name != "", "loom: a registered theme needs a name")
	entry := t
	if old, ok := ctx.themes[t.name]; ok {
		entry.name = old.name
		ctx.themes[entry.name] = entry
		return
	}
	entry.name = strings.clone(t.name, ctx.allocator)
	ctx.themes[entry.name] = entry
}

theme_names :: proc(allocator := context.allocator) -> []string {
	ctx := ctx_of()
	out := make([dynamic]string, 0, len(BUILTIN_THEMES) + len(ctx.themes), allocator)
	for t in BUILTIN_THEMES {
		append(&out, t.name)
	}
	for name in ctx.themes {
		if _, builtin := builtin_theme(name); builtin {
			continue
		}
		append(&out, name)
	}
	slice.sort(out[:])
	return out[:]
}

@(private)
builtin_theme :: proc(name: string) -> (Theme, bool) {
	for t in BUILTIN_THEMES {
		if t.name == name {
			return t, true
		}
	}
	return {}, false
}

@(private)
free_themes :: proc(ctx: ^Context) {
	for name in ctx.themes {
		delete(name, ctx.allocator)
	}
	delete(ctx.themes)
	ctx.themes = {}
}
