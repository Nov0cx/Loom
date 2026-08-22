package loom

import "base:runtime"
import ini "core:encoding/ini"
import "core:fmt"
import "core:strconv"
import "core:strings"

INI_VERSION :: "0.1"

INI_SECTION_LOOM :: "loom"
INI_SECTION_THEME :: "theme"
INI_SECTION_NODE :: "node"
INI_SECTION_APP :: "app"

INI_OPTIONS :: ini.Options {
	comment        = ";",
	key_lower_case = false,
}

Ini_Entry :: struct {
	section: string,
	name:    string,
	key:     string,
	value:   string,
}

ini_entries :: proc(data: string, allocator: runtime.Allocator) -> []Ini_Entry {
	out := make([dynamic]Ini_Entry, 0, 32, allocator)
	it := ini.iterator_from_string(data, INI_OPTIONS)
	for key, value in ini.iterate(&it) {
		head, name := ini_split_section(it.section)
		append(&out, Ini_Entry{head, name, key, ini_unquote(value)})
	}
	return out[:]
}

@(private)
ini_split_section :: proc(section: string) -> (head, name: string) {
	dot := strings.index_byte(section, '.')
	if dot < 0 {
		return section, ""
	}
	return section[:dot], section[dot + 1:]
}

@(private)
ini_split_last :: proc(key: string) -> (head, tail: string, ok: bool) {
	dot := strings.last_index_byte(key, '.')
	if dot <= 0 || dot == len(key) - 1 {
		return "", "", false
	}
	return key[:dot], key[dot + 1:], true
}

@(private)
ini_unquote :: proc(v: string) -> string {
	if len(v) >= 2 && (v[0] == '"' || v[0] == '\'') && v[len(v) - 1] == v[0] {
		return v[1:len(v) - 1]
	}
	return v
}

parse_color :: proc(s: string) -> (Color, bool) {
	v := ini_unquote(strings.trim_space(s))
	if len(v) > 0 && v[0] == '#' {
		v = v[1:]
	}
	if len(v) != 6 && len(v) != 8 {
		return {}, false
	}
	n: u32
	for i in 0 ..< len(v) {
		d, ok := hex_digit(v[i])
		if !ok {
			return {}, false
		}
		n = n << 4 | u32(d)
	}
	if len(v) == 6 {
		return {u8(n >> 16), u8(n >> 8), u8(n), 255}, true
	}
	return {u8(n >> 24), u8(n >> 16), u8(n >> 8), u8(n)}, true
}

@(private)
hex_digit :: proc(c: byte) -> (u8, bool) {
	switch c {
	case '0' ..= '9':
		return c - '0', true
	case 'a' ..= 'f':
		return c - 'a' + 10, true
	case 'A' ..= 'F':
		return c - 'A' + 10, true
	}
	return 0, false
}

parse_bool :: proc(s: string) -> (bool, bool) {
	switch strings.trim_space(ini_unquote(s)) {
	case "true", "1", "yes", "on":
		return true, true
	case "false", "0", "no", "off":
		return false, true
	}
	return false, false
}

parse_f32 :: proc(s: string) -> (f32, bool) {
	return strconv.parse_f32(strings.trim_space(ini_unquote(s)))
}

parse_vec2 :: proc(s: string) -> (Vec2, bool) {
	v := strings.trim_space(ini_unquote(s))
	sep := strings.index_any(v, " \t,")
	if sep <= 0 {
		return {}, false
	}
	x, xok := strconv.parse_f32(strings.trim_space(v[:sep]))
	y, yok := strconv.parse_f32(strings.trim_space(v[sep + 1:]))
	if !xok || !yok {
		return {}, false
	}
	return {x, y}, true
}

color_string :: proc(c: Color, allocator: runtime.Allocator) -> string {
	if c[3] == 255 {
		return fmt.aprintf("#%02X%02X%02X", c[0], c[1], c[2], allocator = allocator)
	}
	return fmt.aprintf("#%02X%02X%02X%02X", c[0], c[1], c[2], c[3], allocator = allocator)
}

vec2_string :: proc(v: Vec2, allocator: runtime.Allocator) -> string {
	return fmt.aprintf("%v %v", v.x, v.y, allocator = allocator)
}

f32_string :: proc(v: f32, allocator: runtime.Allocator) -> string {
	return fmt.aprintf("%v", v, allocator = allocator)
}

bool_string :: proc(v: bool) -> string {
	return v ? "true" : "false"
}

ini_write_section :: proc(w: Writer, name: string) {
	ini.write_section(w, name)
}

ini_write_pair :: proc(w: Writer, key, value: string) {
	ini.write_pair(w, key, value)
}
