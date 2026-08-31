package ui_sokol

import sg "../../third_party/sokol/sokol/gfx"

Vertex :: struct {
	pos: [2]f32,
	uv:  [2]f32,
	col: [4]u8,
}

Uniforms :: struct {
	size: [2]f32,
	pad:  [2]f32,
}

GL_VS :: `#version 410
layout(location=0) in vec2 a_pos;
layout(location=1) in vec2 a_uv;
layout(location=2) in vec4 a_col;
uniform vec4 u_size;
out vec2 v_uv;
out vec4 v_col;
void main() {
	v_uv = a_uv;
	v_col = a_col;
	gl_Position = vec4(a_pos.x / u_size.x * 2.0 - 1.0, 1.0 - a_pos.y / u_size.y * 2.0, 0.0, 1.0);
}
`

GL_FS :: `#version 410
in vec2 v_uv;
in vec4 v_col;
out vec4 o_col;
uniform sampler2D u_tex;
void main() { o_col = v_col * texture(u_tex, v_uv); }
`

HLSL_VS :: `
cbuffer U : register(b0) { float4 u_size; };
struct VS_In  { float2 pos : TEXCOORD0; float2 uv : TEXCOORD1; float4 col : TEXCOORD2; };
struct VS_Out { float4 pos : SV_Position; float2 uv : TEXCOORD0; float4 col : TEXCOORD1; };
VS_Out vs_main(VS_In i) {
	VS_Out o;
	o.pos = float4(i.pos.x / u_size.x * 2.0 - 1.0, 1.0 - i.pos.y / u_size.y * 2.0, 0.0, 1.0);
	o.uv = i.uv;
	o.col = i.col;
	return o;
}
`

HLSL_FS :: `
struct VS_Out { float4 pos : SV_Position; float2 uv : TEXCOORD0; float4 col : TEXCOORD1; };
Texture2D u_tex : register(t0);
SamplerState u_smp : register(s0);
float4 ps_main(VS_Out i) : SV_Target { return i.col * u_tex.Sample(u_smp, i.uv); }
`

MSL_VS :: `#include <metal_stdlib>
using namespace metal;
struct params_t { float4 u_size; };
struct vs_in { float2 pos [[attribute(0)]]; float2 uv [[attribute(1)]]; float4 col [[attribute(2)]]; };
struct vs_out { float4 pos [[position]]; float2 uv; float4 col; };
vertex vs_out vs_main(vs_in in [[stage_in]], constant params_t& p [[buffer(0)]]) {
	vs_out o;
	o.pos = float4(in.pos.x / p.u_size.x * 2.0 - 1.0, 1.0 - in.pos.y / p.u_size.y * 2.0, 0.0, 1.0);
	o.uv = in.uv;
	o.col = in.col;
	return o;
}
`

MSL_FS :: `#include <metal_stdlib>
using namespace metal;
struct vs_out { float4 pos [[position]]; float2 uv; float4 col; };
fragment float4 fs_main(vs_out in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler smp [[sampler(0)]]) {
	return in.col * tex.sample(smp, in.uv);
}
`

@(private)
make_shader :: proc(b: ^Backend) -> bool {
	desc: sg.Shader_Desc
	desc.label = "loom_ui"

	switch sg.query_backend() {
	case .GLCORE, .GLES3:
		desc.vertex_func = {source = GL_VS}
		desc.fragment_func = {source = GL_FS}
	case .D3D11:
		desc.vertex_func = {source = HLSL_VS, entry = "vs_main", d3d11_target = "vs_4_0"}
		desc.fragment_func = {source = HLSL_FS, entry = "ps_main", d3d11_target = "ps_4_0"}
	case .METAL_MACOS, .METAL_IOS, .METAL_SIMULATOR:
		desc.vertex_func = {source = MSL_VS, entry = "vs_main"}
		desc.fragment_func = {source = MSL_FS, entry = "fs_main"}
	case .WGPU, .VULKAN, .DUMMY:
		return fail(b, "ui_sokol: this backend needs GLCORE, D3D11 or Metal")
	}

	desc.attrs[0] = {
		base_type      = .FLOAT,
		glsl_name      = "a_pos",
		hlsl_sem_name  = "TEXCOORD",
		hlsl_sem_index = 0,
	}
	desc.attrs[1] = {
		base_type      = .FLOAT,
		glsl_name      = "a_uv",
		hlsl_sem_name  = "TEXCOORD",
		hlsl_sem_index = 1,
	}
	desc.attrs[2] = {
		base_type      = .FLOAT,
		glsl_name      = "a_col",
		hlsl_sem_name  = "TEXCOORD",
		hlsl_sem_index = 2,
	}

	desc.uniform_blocks[0] = {
		stage                 = .VERTEX,
		size                  = size_of(Uniforms),
		hlsl_register_b_n     = 0,
		msl_buffer_n          = 0,
		wgsl_group0_binding_n = 0,
		layout                = .STD140,
	}
	desc.uniform_blocks[0].glsl_uniforms[0] = {
		type        = .FLOAT4,
		array_count = 1,
		glsl_name   = "u_size",
	}

	desc.views[0].texture = {
		stage                 = .FRAGMENT,
		image_type            = ._2D,
		sample_type           = .FLOAT,
		multisampled          = false,
		hlsl_register_t_n     = 0,
		msl_texture_n         = 0,
		wgsl_group1_binding_n = 0,
	}
	desc.samplers[0] = {
		stage                 = .FRAGMENT,
		sampler_type          = .FILTERING,
		hlsl_register_s_n     = 0,
		msl_sampler_n         = 0,
		wgsl_group1_binding_n = 1,
	}
	desc.texture_sampler_pairs[0] = {
		stage        = .FRAGMENT,
		view_slot    = 0,
		sampler_slot = 0,
		glsl_name    = "u_tex",
	}

	b.shader = sg.make_shader(desc)
	return true
}

@(private)
make_pipeline :: proc(b: ^Backend, samples: int) -> bool {
	pd := sg.Pipeline_Desc {
		shader = b.shader,
		index_type = .UINT32,
		primitive_type = .TRIANGLES,
		cull_mode = .NONE,
		sample_count = i32(samples),
		label = "loom_ui",
	}
	pd.layout.attrs[0] = {
		format = .FLOAT2,
		offset = i32(offset_of(Vertex, pos)),
	}
	pd.layout.attrs[1] = {
		format = .FLOAT2,
		offset = i32(offset_of(Vertex, uv)),
	}
	pd.layout.attrs[2] = {
		format = .UBYTE4N,
		offset = i32(offset_of(Vertex, col)),
	}
	pd.layout.buffers[0].stride = size_of(Vertex)

	pd.depth = {
		write_enabled = false,
		compare       = .ALWAYS,
	}
	pd.colors[0].blend = {
		enabled          = true,
		src_factor_rgb   = .SRC_ALPHA,
		dst_factor_rgb   = .ONE_MINUS_SRC_ALPHA,
		op_rgb           = .ADD,
		src_factor_alpha = .ONE,
		dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
		op_alpha         = .ADD,
	}

	b.pip = sg.make_pipeline(pd)

	b.smp = sg.make_sampler(
		{
			min_filter = .LINEAR,
			mag_filter = .LINEAR,
			wrap_u = .CLAMP_TO_EDGE,
			wrap_v = .CLAMP_TO_EDGE,
			label = "loom_ui",
		},
	)
	return true
}
