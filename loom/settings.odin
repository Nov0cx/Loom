package loom

import "base:runtime"
import ini "core:encoding/ini"
import "core:io"
import "core:slice"
import "core:strings"

Settings_Handler :: struct {
	section: string,
	read:    proc(name, key, value: string, user: rawptr),
	write:   proc(w: Writer, user: rawptr),
	user:    rawptr,
}

Persist :: struct {
	scroll: Vec2,
	open:   bool,
}

settings_handler :: proc(h: Settings_Handler) {
	settings_handler_ctx(ctx_of(), h)
}

@(private)
settings_handler_ctx :: proc(ctx: ^Context, h: Settings_Handler) {
	assert(h.section != "", "loom: a settings handler needs a section name")
	for &existing in ctx.handlers {
		if existing.section == h.section {
			existing = h
			return
		}
	}
	append(&ctx.handlers, h)
}

settings_dirty :: proc() {
	mark_dirty(ctx_of())
}

settings_is_dirty :: proc() -> bool {
	return ctx_of().settings_dirty
}

@(private)
mark_dirty :: proc(ctx: ^Context) {
	ctx.settings_dirty = true
}

settings_load :: proc(data: []byte) -> bool {
	return settings_load_ctx(ctx_of(), data)
}

@(private)
settings_load_ctx :: proc(ctx: ^Context, data: []byte) -> bool {
	entries := ini_entries(string(data), ctx.frame_allocator)
	if len(entries) == 0 {
		return false
	}

	load_themes(ctx, entries)

	used := 0
	for e in entries {
		switch e.section {
		case INI_SECTION_THEME:
			used += 1
		case INI_SECTION_LOOM:
			if e.key == "theme" {
				if t, ok := theme_by_name_ctx(ctx, e.value); ok {
					ctx.theme = t
				}
			}
			used += 1
		case INI_SECTION_NODE:
			if load_node(ctx, e.key, e.value) {
				used += 1
			}
		case INI_SECTION_APP:
			store_setting(ctx, e.key, e.value)
			used += 1
		case:
			for h in ctx.handlers {
				if h.section == e.section && h.read != nil {
					h.read(e.name, e.key, e.value, h.user)
					used += 1
					break
				}
			}
		}
	}

	ctx.settings_dirty = false
	return used > 0
}

@(private)
load_themes :: proc(ctx: ^Context, entries: []Ini_Entry) {
	name := ""
	cur: Theme

	for e in entries {
		if e.section != INI_SECTION_THEME || e.name == "" {
			continue
		}
		if e.name != name {
			if name != "" {
				register_theme_ctx(ctx, cur)
			}
			name = e.name
			cur = DEFAULT_THEME
			cur.name = e.name
		}
		switch e.key {
		case "base":
			if b, ok := theme_by_name_ctx(ctx, e.value); ok {
				based := b
				based.name = cur.name
				cur = based
			}
		case "dark":
			if v, ok := parse_bool(e.value); ok {
				cur.dark = v
			}
		case:
			if slot := theme_slot(&cur, e.key); slot != nil {
				if c, ok := parse_color(e.value); ok {
					slot^ = c
				}
			}
		}
	}
	if name != "" {
		register_theme_ctx(ctx, cur)
	}
}

@(private)
load_node :: proc(ctx: ^Context, key, value: string) -> bool {
	path, field, ok := ini_split_last(key)
	if !ok {
		return false
	}
	switch field {
	case "scroll":
		v, vok := parse_vec2(value)
		if !vok {
			return false
		}
		entry_for_path(ctx, path).scroll = v
	case "open":
		v, vok := parse_bool(value)
		if !vok {
			return false
		}
		entry_for_path(ctx, path).open = v
	case:
		return false
	}
	return true
}

settings_save :: proc(w: Writer) {
	settings_save_ctx(ctx_of(), w)
}

settings_save_string :: proc(allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	settings_save_ctx(ctx_of(), strings.to_writer(&b))
	return strings.to_string(b)
}

@(private)
settings_save_ctx :: proc(ctx: ^Context, w: Writer) {
	ini.write_section(w, INI_SECTION_LOOM)
	ini.write_pair(w, "version", INI_VERSION)
	ini.write_pair(w, "theme", ctx.theme.name)

	for name in sorted_keys(ctx, ctx.themes) {
		blank(w)
		write_theme(ctx, w, ctx.themes[name])
	}

	if len(ctx.persist) > 0 {
		paths := sorted_keys(ctx, ctx.persist)
		wrote := false
		for path in paths {
			p := ctx.persist[path]
			if p.scroll == {} && !p.open {
				continue
			}
			if !wrote {
				blank(w)
				ini.write_section(w, INI_SECTION_NODE)
				wrote = true
			}
			if p.scroll != {} {
				ini.write_pair(
					w,
					strings.concatenate({path, ".scroll"}, ctx.frame_allocator),
					vec2_string(p.scroll, ctx.frame_allocator),
				)
			}
			if p.open {
				ini.write_pair(
					w,
					strings.concatenate({path, ".open"}, ctx.frame_allocator),
					bool_string(p.open),
				)
			}
		}
	}

	if len(ctx.settings) > 0 {
		blank(w)
		ini.write_section(w, INI_SECTION_APP)
		for key in sorted_keys(ctx, ctx.settings) {
			ini.write_pair(w, key, ctx.settings[key])
		}
	}

	for h in ctx.handlers {
		if h.write == nil {
			continue
		}
		blank(w)
		h.write(w, h.user)
	}

	ctx.settings_dirty = false
}

@(private)
blank :: proc(w: Writer) {
	io.write_byte(w, '\n')
}

@(private)
write_theme :: proc(ctx: ^Context, w: Writer, t: Theme) {
	ini.write_section(
		w,
		strings.concatenate({INI_SECTION_THEME, ".", t.name}, ctx.frame_allocator),
	)
	ini.write_pair(w, "dark", bool_string(t.dark))
	tt := t
	for s in THEME_SLOTS {
		c := (^Color)(uintptr(&tt) + s.offset)^
		ini.write_pair(w, s.name, color_string(c, ctx.frame_allocator))
	}
}

@(private)
sorted_keys :: proc(ctx: ^Context, m: $M/map[string]$V) -> []string {
	out := make([dynamic]string, 0, len(m), ctx.frame_allocator)
	for key in m {
		append(&out, key)
	}
	slice.sort(out[:])
	return out[:]
}

setting_string :: proc(key: string, def: string = "") -> string {
	if v, ok := ctx_of().settings[key]; ok {
		return v
	}
	return def
}

setting_bool :: proc(key: string, def: bool = false) -> bool {
	if v, ok := ctx_of().settings[key]; ok {
		if b, bok := parse_bool(v); bok {
			return b
		}
	}
	return def
}

setting_f32 :: proc(key: string, def: f32 = 0) -> f32 {
	if v, ok := ctx_of().settings[key]; ok {
		if f, fok := parse_f32(v); fok {
			return f
		}
	}
	return def
}

setting_vec2 :: proc(key: string, def: Vec2 = {}) -> Vec2 {
	if v, ok := ctx_of().settings[key]; ok {
		if p, pok := parse_vec2(v); pok {
			return p
		}
	}
	return def
}

set_setting_string :: proc(key: string, value: string) {
	ctx := ctx_of()
	store_setting(ctx, key, value)
	mark_dirty(ctx)
}

set_setting_bool :: proc(key: string, value: bool) {
	set_setting_string(key, bool_string(value))
}

set_setting_f32 :: proc(key: string, value: f32) {
	ctx := ctx_of()
	store_setting(ctx, key, f32_string(value, ctx.frame_allocator))
	mark_dirty(ctx)
}

set_setting_vec2 :: proc(key: string, value: Vec2) {
	ctx := ctx_of()
	store_setting(ctx, key, vec2_string(value, ctx.frame_allocator))
	mark_dirty(ctx)
}

set_setting :: proc {
	set_setting_string,
	set_setting_bool,
	set_setting_f32,
	set_setting_vec2,
}

@(private)
store_setting :: proc(ctx: ^Context, key, value: string) {
	if old, ok := ctx.settings[key]; ok {
		if old == value {
			return
		}
		delete(old, ctx.allocator)
		ctx.settings[key] = strings.clone(value, ctx.allocator)
		return
	}
	ctx.settings[strings.clone(key, ctx.allocator)] = strings.clone(value, ctx.allocator)
}

persist :: proc(loc := #caller_location) -> ^Persist {
	ctx := ctx_of(loc)
	assert(len(ctx.open) > 0, "loom: persist called outside a frame", loc)
	return persist_of(ctx.open[len(ctx.open) - 1].node, loc)
}

persist_of :: proc(n: ^Node, loc := #caller_location) -> ^Persist {
	ctx := ctx_of(loc)
	if n.persist == nil {
		bind_persist(ctx, n, loc)
	}
	return n.persist
}

@(private)
bind_persist :: proc(ctx: ^Context, n: ^Node, loc: runtime.Source_Code_Location) {
	path, ok := node_path(ctx, n)
	if !ok {
		when ODIN_DEBUG {
			panic(
				"loom: a persisted node needs a stable Element.key on itself and every ancestor",
				loc,
			)
		} else {
			n.persist = entry_for_path(ctx, "")
			return
		}
	}
	known := path in ctx.persist
	entry := entry_for_path(ctx, path)
	n.persist = entry
	if known && n.first_frame {
		n.scroll = entry.scroll
	}
}

@(private)
entry_for_path :: proc(ctx: ^Context, path: string) -> ^Persist {
	if p, ok := ctx.persist[path]; ok {
		return p
	}
	p, err := new(Persist, ctx.allocator)
	assert(err == nil, "loom: out of memory allocating a persist entry")
	ctx.persist[strings.clone(path, ctx.allocator)] = p
	return p
}

@(private)
node_path :: proc(ctx: ^Context, n: ^Node) -> (string, bool) {
	parts := make([dynamic]string, 0, 8, ctx.frame_allocator)
	for p := n; p != nil && p != ctx.root; p = p.parent {
		if p.el.key == "" {
			return "", false
		}
		append(&parts, p.el.key)
	}
	if len(parts) == 0 {
		return "", false
	}
	slice.reverse(parts[:])
	return strings.join(parts[:], "/", ctx.frame_allocator), true
}

@(private)
sync_persist :: proc(ctx: ^Context, n: ^Node) {
	if n.persist != nil && n.persist.scroll != n.scroll {
		n.persist.scroll = n.scroll
		mark_dirty(ctx)
	}
	for c := n.first_child; c != nil; c = c.next {
		sync_persist(ctx, c)
	}
}

@(private)
free_persist :: proc(ctx: ^Context) {
	for path, p in ctx.persist {
		free(p, ctx.allocator)
		delete(path, ctx.allocator)
	}
	delete(ctx.persist)
	ctx.persist = {}
}

@(private)
free_settings :: proc(ctx: ^Context) {
	for key, value in ctx.settings {
		delete(key, ctx.allocator)
		delete(value, ctx.allocator)
	}
	delete(ctx.settings)
	ctx.settings = {}
	delete(ctx.handlers)
	ctx.handlers = {}
}
