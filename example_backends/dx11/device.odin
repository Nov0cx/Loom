package ui_dx11

import "core:fmt"
import "core:mem"
import win "core:sys/windows"
import d3d "vendor:directx/d3d11"
import dxc "vendor:directx/d3d_compiler"
import "vendor:directx/dxgi"

Vertex :: struct {
	pos: [2]f32,
	uv:  [2]f32,
	col: [4]u8,
}

Uniforms :: struct {
	size: [2]f32,
	pad:  [2]f32,
}

Buf :: struct {
	buf:  ^d3d.IBuffer,
	size: int,
}

MIN_BUF :: 4096

SHADER_SRC :: `
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

Texture2D u_tex : register(t0);
SamplerState u_smp : register(s0);

float4 ps_main(VS_Out i) : SV_Target { return i.col * u_tex.Sample(u_smp, i.uv); }
`

@(rodata)
VERTEX_ATTRS := [3]d3d.INPUT_ELEMENT_DESC {
	{"TEXCOORD", 0, .R32G32_FLOAT, 0, 0, .VERTEX_DATA, 0},
	{"TEXCOORD", 1, .R32G32_FLOAT, 0, 8, .VERTEX_DATA, 0},
	{"TEXCOORD", 2, .R8G8B8A8_UNORM, 0, 16, .VERTEX_DATA, 0},
}

@(rodata)
LEVELS := [2]d3d.FEATURE_LEVEL{._11_0, ._10_1}

@(private)
fail :: proc(b: ^Backend, msg: string) -> bool {
	if b.err == "" {
		b.err = msg
	}
	return false
}

@(private)
make_device :: proc(b: ^Backend) -> bool {
	flags := d3d.CREATE_DEVICE_FLAGS{.BGRA_SUPPORT}
	when ODIN_DEBUG {
		flags += {.DEBUG}
	}

	hr := d3d.CreateDevice(
		nil,
		.HARDWARE,
		nil,
		flags,
		raw_data(LEVELS[:]),
		u32(len(LEVELS)),
		d3d.SDK_VERSION,
		&b.device,
		nil,
		&b.dctx,
	)
	if !win.SUCCEEDED(hr) && .DEBUG in flags {
		flags -= {.DEBUG}
		hr = d3d.CreateDevice(
			nil,
			.HARDWARE,
			nil,
			flags,
			raw_data(LEVELS[:]),
			u32(len(LEVELS)),
			d3d.SDK_VERSION,
			&b.device,
			nil,
			&b.dctx,
		)
	}
	if !win.SUCCEEDED(hr) {
		return fail(b, "ui_dx11: no Direct3D 11 device")
	}

	dxdev: ^dxgi.IDevice
	if !win.SUCCEEDED(b.device->QueryInterface(dxgi.IDevice_UUID, (^rawptr)(&dxdev))) {
		return fail(b, "ui_dx11: the device is not a DXGI device")
	}
	defer dxdev->Release()

	adapter: ^dxgi.IAdapter
	if !win.SUCCEEDED(dxdev->GetAdapter(&adapter)) {
		return fail(b, "ui_dx11: the device has no DXGI adapter")
	}
	defer adapter->Release()

	if !win.SUCCEEDED(adapter->GetParent(dxgi.IFactory_UUID, (^rawptr)(&b.factory))) {
		return fail(b, "ui_dx11: the adapter has no DXGI factory")
	}
	return true
}

@(private)
pick_samples :: proc(b: ^Backend, want: int) -> u32 {
	n := u32(clamp(want, 1, 16))
	for n > 1 {
		levels: u32
		hr := b.device->CheckMultisampleQualityLevels(.R8G8B8A8_UNORM, n, &levels)
		if win.SUCCEEDED(hr) && levels > 0 {
			return n
		}
		n /= 2
	}
	return 1
}

@(private)
compile_stage :: proc(b: ^Backend, entry, target: cstring) -> ^d3d.IBlob {
	flags := u32(1) << u32(dxc.D3DCOMPILE_FLAG.ENABLE_STRICTNESS)
	flags |= u32(1) << u32(dxc.D3DCOMPILE_FLAG.OPTIMIZATION_LEVEL3)

	src: string = SHADER_SRC
	code, errs: ^d3d.IBlob
	hr := dxc.Compile(
		raw_data(src),
		len(src),
		"loom_ui.hlsl",
		nil,
		nil,
		entry,
		target,
		flags,
		0,
		&code,
		&errs,
	)
	if errs != nil {
		fmt.eprintfln("ui_dx11: %s", cstring(errs->GetBufferPointer()))
		errs->Release()
	}
	if !win.SUCCEEDED(hr) {
		if code != nil {
			code->Release()
		}
		return nil
	}
	return code
}

@(private)
make_shaders :: proc(b: ^Backend) -> bool {
	vsb := compile_stage(b, "vs_main", "vs_4_0")
	if vsb == nil {
		return fail(b, "ui_dx11: the vertex shader did not compile")
	}
	defer vsb->Release()

	psb := compile_stage(b, "ps_main", "ps_4_0")
	if psb == nil {
		return fail(b, "ui_dx11: the pixel shader did not compile")
	}
	defer psb->Release()

	hr := b.device->CreateVertexShader(vsb->GetBufferPointer(), vsb->GetBufferSize(), nil, &b.vs)
	if !win.SUCCEEDED(hr) {
		return fail(b, "ui_dx11: could not create the vertex shader")
	}

	hr = b.device->CreatePixelShader(psb->GetBufferPointer(), psb->GetBufferSize(), nil, &b.ps)
	if !win.SUCCEEDED(hr) {
		return fail(b, "ui_dx11: could not create the pixel shader")
	}

	hr = b.device->CreateInputLayout(
		raw_data(VERTEX_ATTRS[:]),
		u32(len(VERTEX_ATTRS)),
		vsb->GetBufferPointer(),
		vsb->GetBufferSize(),
		&b.input,
	)
	if !win.SUCCEEDED(hr) {
		return fail(b, "ui_dx11: could not create the input layout")
	}

	cb := d3d.BUFFER_DESC {
		ByteWidth      = size_of(Uniforms),
		Usage          = .DYNAMIC,
		BindFlags      = {.CONSTANT_BUFFER},
		CPUAccessFlags = {.WRITE},
	}
	if !win.SUCCEEDED(b.device->CreateBuffer(&cb, nil, &b.cbuf)) {
		return fail(b, "ui_dx11: could not create the constant buffer")
	}
	return true
}

@(private)
make_states :: proc(b: ^Backend) -> bool {
	bd: d3d.BLEND_DESC
	bd.RenderTarget[0] = {
		BlendEnable           = true,
		SrcBlend              = .SRC_ALPHA,
		DestBlend             = .INV_SRC_ALPHA,
		BlendOp               = .ADD,
		SrcBlendAlpha         = .ONE,
		DestBlendAlpha        = .INV_SRC_ALPHA,
		BlendOpAlpha          = .ADD,
		RenderTargetWriteMask = 0xF,
	}
	if !win.SUCCEEDED(b.device->CreateBlendState(&bd, &b.blend)) {
		return fail(b, "ui_dx11: could not create the blend state")
	}

	rd := d3d.RASTERIZER_DESC {
		FillMode          = .SOLID,
		CullMode          = .NONE,
		DepthClipEnable   = true,
		ScissorEnable     = true,
		MultisampleEnable = b3(b.samples > 1),
	}
	if !win.SUCCEEDED(b.device->CreateRasterizerState(&rd, &b.raster)) {
		return fail(b, "ui_dx11: could not create the rasteriser state")
	}

	dd := d3d.DEPTH_STENCIL_DESC {
		DepthEnable    = false,
		DepthWriteMask = .ZERO,
		DepthFunc      = .ALWAYS,
	}
	if !win.SUCCEEDED(b.device->CreateDepthStencilState(&dd, &b.depth)) {
		return fail(b, "ui_dx11: could not create the depth state")
	}

	sd := d3d.SAMPLER_DESC {
		Filter         = .MIN_MAG_MIP_LINEAR,
		AddressU       = .CLAMP,
		AddressV       = .CLAMP,
		AddressW       = .CLAMP,
		ComparisonFunc = .ALWAYS,
	}
	if !win.SUCCEEDED(b.device->CreateSamplerState(&sd, &b.sampler)) {
		return fail(b, "ui_dx11: could not create the sampler")
	}
	return true
}

@(private)
b3 :: proc(v: bool) -> win.BOOL {
	return win.BOOL(v)
}

make_raw_texture :: proc(
	b: ^Backend,
	w, h: int,
	pixels: []u8,
) -> (
	tex: ^d3d.ITexture2D,
	srv: ^d3d.IShaderResourceView,
	ok: bool,
) {
	td := d3d.TEXTURE2D_DESC {
		Width      = u32(w),
		Height     = u32(h),
		MipLevels  = 1,
		ArraySize  = 1,
		Format     = .R8G8B8A8_UNORM,
		SampleDesc = {Count = 1},
		Usage      = .DEFAULT,
		BindFlags  = {.SHADER_RESOURCE},
	}

	if pixels != nil {
		sub := d3d.SUBRESOURCE_DATA {
			pSysMem     = raw_data(pixels),
			SysMemPitch = u32(w * 4),
		}
		if !win.SUCCEEDED(b.device->CreateTexture2D(&td, &sub, &tex)) {
			return nil, nil, false
		}
	} else if !win.SUCCEEDED(b.device->CreateTexture2D(&td, nil, &tex)) {
		return nil, nil, false
	}

	vd := d3d.SHADER_RESOURCE_VIEW_DESC {
		Format        = .R8G8B8A8_UNORM,
		ViewDimension = .TEXTURE2D,
	}
	vd.Texture2D = {
		MostDetailedMip = 0,
		MipLevels       = 1,
	}
	if !win.SUCCEEDED(b.device->CreateShaderResourceView(tex, &vd, &srv)) {
		tex->Release()
		return nil, nil, false
	}
	return tex, srv, true
}

@(private)
make_white :: proc(b: ^Backend) -> bool {
	px := [4]u8{255, 255, 255, 255}
	tex, srv, ok := make_raw_texture(b, 1, 1, px[:])
	if !ok {
		return fail(b, "ui_dx11: could not create the white texture")
	}
	b.white = {
		tex   = tex,
		srv   = srv,
		w     = 1,
		h     = 1,
		owned = true,
	}
	return true
}

@(private)
grow_buffer :: proc(b: ^Backend, buf: ^Buf, bytes: int, bind: d3d.BIND_FLAGS) -> bool {
	if buf.buf != nil && buf.size >= bytes {
		return true
	}
	if buf.buf != nil {
		buf.buf->Release()
		buf.buf = nil
	}

	size := max(bytes, buf.size * 2, MIN_BUF)
	bd := d3d.BUFFER_DESC {
		ByteWidth      = u32(size),
		Usage          = .DYNAMIC,
		BindFlags      = bind,
		CPUAccessFlags = {.WRITE},
	}
	if !win.SUCCEEDED(b.device->CreateBuffer(&bd, nil, &buf.buf)) {
		buf.size = 0
		return false
	}
	buf.size = size
	return true
}

@(private)
write_buffer :: proc(b: ^Backend, buf: ^d3d.IBuffer, src: rawptr, bytes: int) -> bool {
	if buf == nil {
		return false
	}
	m: d3d.MAPPED_SUBRESOURCE
	if !win.SUCCEEDED(b.dctx->Map(buf, 0, .WRITE_DISCARD, {}, &m)) {
		return false
	}
	mem.copy(m.pData, src, bytes)
	b.dctx->Unmap(buf, 0)
	return true
}

@(private)
make_swapchain :: proc(b: ^Backend, t: ^Target, hwnd: win.HWND) -> bool {
	t.hwnd = hwnd
	t.w, t.h = client_size(hwnd)

	sd := dxgi.SWAP_CHAIN_DESC {
		BufferDesc = {
			Width = u32(max(t.w, 1)),
			Height = u32(max(t.h, 1)),
			Format = .R8G8B8A8_UNORM,
		},
		SampleDesc = {Count = b.samples},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		BufferCount = 2,
		OutputWindow = hwnd,
		Windowed = true,
		SwapEffect = .DISCARD,
	}
	if !win.SUCCEEDED(b.factory->CreateSwapChain(b.device, &sd, &t.swap)) {
		return false
	}
	return make_rtv(b, t)
}

@(private)
make_rtv :: proc(b: ^Backend, t: ^Target) -> bool {
	back: ^d3d.ITexture2D
	if !win.SUCCEEDED(t.swap->GetBuffer(0, d3d.ITexture2D_UUID, (^rawptr)(&back))) {
		return false
	}
	defer back->Release()

	return win.SUCCEEDED(b.device->CreateRenderTargetView(back, nil, &t.rtv))
}

@(private)
ensure_target :: proc(b: ^Backend, t: ^Target) -> bool {
	if t.swap == nil {
		return false
	}
	w, h := client_size(t.hwnd)
	if w <= 0 || h <= 0 {
		return false
	}
	if !t.resized && t.rtv != nil && t.w == w && t.h == h {
		return true
	}

	t.w, t.h = w, h
	t.resized = false

	b.dctx->OMSetRenderTargets(0, nil, nil)
	if t.rtv != nil {
		t.rtv->Release()
		t.rtv = nil
	}
	if !win.SUCCEEDED(t.swap->ResizeBuffers(0, 0, 0, .UNKNOWN, {})) {
		return false
	}
	return make_rtv(b, t)
}

@(private)
destroy_target :: proc(b: ^Backend, t: ^Target) {
	if t.rtv != nil {
		b.dctx->OMSetRenderTargets(0, nil, nil)
		t.rtv->Release()
		t.rtv = nil
	}
	if t.swap != nil {
		t.swap->SetFullscreenState(false, nil)
		t.swap->Release()
		t.swap = nil
	}
	t.hwnd = nil
}
