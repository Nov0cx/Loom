struct V_In {
	[[vk::location(0)]] float2 pos : POSITION;
	[[vk::location(1)]] float2 uv  : TEXCOORD0;
	[[vk::location(2)]] float4 col : COLOR0;
};

struct V_Out {
	float4 pos : SV_Position;
	[[vk::location(0)]] float2 uv  : TEXCOORD0;
	[[vk::location(1)]] float4 col : COLOR0;
};

struct Push {
	float2 size;
};

[[vk::push_constant]] ConstantBuffer<Push> pc;

[[vk::binding(0, 0)]] Sampler2D tex;

[shader("vertex")]
V_Out vs_main(V_In i) {
	V_Out o;
	o.pos = float4(i.pos.x / pc.size.x * 2.0 - 1.0, i.pos.y / pc.size.y * 2.0 - 1.0, 0.0, 1.0);
	o.uv = i.uv;
	o.col = i.col;
	return o;
}

[shader("fragment")]
float4 fs_main(V_Out i) : SV_Target {
	return i.col * tex.Sample(i.uv);
}
