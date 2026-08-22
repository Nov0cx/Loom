package ui_opengl

import gl "vendor:OpenGL"

Vertex :: struct {
	pos: [2]f32,
	uv:  [2]f32,
	col: [4]u8,
}

VERT_SRC :: `#version 330 core
layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec2 a_uv;
layout(location = 2) in vec4 a_col;
uniform vec2 u_size;
out vec2 v_uv;
out vec4 v_col;
void main() {
	v_uv = a_uv;
	v_col = a_col;
	gl_Position = vec4(a_pos.x / u_size.x * 2.0 - 1.0, 1.0 - a_pos.y / u_size.y * 2.0, 0.0, 1.0);
}
`

FRAG_SRC :: `#version 330 core
in vec2 v_uv;
in vec4 v_col;
out vec4 o_col;
uniform sampler2D u_tex;
void main() {
	o_col = v_col * texture(u_tex, v_uv);
}
`

@(private)
make_program :: proc() -> (u32, bool) {
	prog, ok := gl.load_shaders_source(VERT_SRC, FRAG_SRC)
	if !ok {
		return 0, false
	}
	return prog, true
}

@(private)
make_buffers :: proc(b: ^Backend) {
	gl.GenBuffers(1, &b.vbo)
	gl.GenBuffers(1, &b.ibo)

	white: [4]u8 = {255, 255, 255, 255}
	gl.GenTextures(1, &b.white)
	gl.BindTexture(gl.TEXTURE_2D, b.white)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(white[:]))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.BindTexture(gl.TEXTURE_2D, 0)
}

@(private)
make_vao :: proc(b: ^Backend) -> u32 {
	vao: u32
	gl.GenVertexArrays(1, &vao)
	gl.BindVertexArray(vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, b.vbo)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, b.ibo)
	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)
	gl.EnableVertexAttribArray(2)
	gl.VertexAttribPointer(0, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, pos))
	gl.VertexAttribPointer(1, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, uv))
	gl.VertexAttribPointer(2, 4, gl.UNSIGNED_BYTE, true, size_of(Vertex), offset_of(Vertex, col))
	gl.BindVertexArray(0)
	return vao
}

@(private)
make_texture :: proc(w, h: int, pixels: rawptr) -> u32 {
	id: u32
	gl.GenTextures(1, &id)
	gl.BindTexture(gl.TEXTURE_2D, id)
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, i32(w), i32(h), 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.BindTexture(gl.TEXTURE_2D, 0)
	return id
}
