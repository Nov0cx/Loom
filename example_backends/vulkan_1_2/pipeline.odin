package ui_vulkan_1_2

import vk "vendor:vulkan"

Vertex :: struct {
	pos: [2]f32,
	uv:  [2]f32,
	col: [4]u8,
}

Push :: struct {
	size: [2]f32,
}

Image :: struct {
	img:    vk.Image,
	mem:    vk.DeviceMemory,
	view:   vk.ImageView,
	set:    vk.DescriptorSet,
	layout: vk.ImageLayout,
	w, h:   int,
}

@(rodata)
VERT_SPV := #load("shaders/ui.vert.spv", []u32)

@(rodata)
FRAG_SPV := #load("shaders/ui.frag.spv", []u32)

@(rodata)
VERTEX_BINDING := [1]vk.VertexInputBindingDescription {
	{binding = 0, stride = size_of(Vertex), inputRate = .VERTEX},
}

@(rodata)
VERTEX_ATTRS := [3]vk.VertexInputAttributeDescription {
	{location = 0, binding = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(Vertex, pos))},
	{location = 1, binding = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(Vertex, uv))},
	{location = 2, binding = 0, format = .R8G8B8A8_UNORM, offset = u32(offset_of(Vertex, col))},
}

@(rodata)
DYNAMIC_STATES := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}

@(private)
make_render_pass :: proc(b: ^Backend) -> bool {
	ms := b.samples != {._1}

	atts: [2]vk.AttachmentDescription
	atts[0] = {
		format         = b.format,
		samples        = b.samples,
		loadOp         = .CLEAR,
		storeOp        = ms ? .DONT_CARE : .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = ms ? .COLOR_ATTACHMENT_OPTIMAL : .PRESENT_SRC_KHR,
	}
	atts[1] = {
		format         = b.format,
		samples        = {._1},
		loadOp         = .DONT_CARE,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}

	color := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}
	resolve := vk.AttachmentReference {
		attachment = 1,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	sub := vk.SubpassDescription {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments    = &color,
		pResolveAttachments  = ms ? &resolve : nil,
	}

	dep := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
	}

	ci := vk.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = ms ? 2 : 1,
		pAttachments    = raw_data(atts[:]),
		subpassCount    = 1,
		pSubpasses      = &sub,
		dependencyCount = 1,
		pDependencies   = &dep,
	}
	return vk.CreateRenderPass(b.device, &ci, nil, &b.pass) == .SUCCESS
}

@(private)
make_desc_layout :: proc(b: ^Backend) -> bool {
	binding := vk.DescriptorSetLayoutBinding {
		binding         = 0,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		descriptorCount = 1,
		stageFlags      = {.FRAGMENT},
	}
	ci := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = &binding,
	}
	return vk.CreateDescriptorSetLayout(b.device, &ci, nil, &b.desc_layout) == .SUCCESS
}

@(private)
make_sampler :: proc(b: ^Backend) -> bool {
	ci := vk.SamplerCreateInfo {
		sType        = .SAMPLER_CREATE_INFO,
		magFilter    = .LINEAR,
		minFilter    = .LINEAR,
		mipmapMode   = .NEAREST,
		addressModeU = .CLAMP_TO_EDGE,
		addressModeV = .CLAMP_TO_EDGE,
		addressModeW = .CLAMP_TO_EDGE,
		maxLod       = 0,
		borderColor  = .FLOAT_TRANSPARENT_BLACK,
	}
	return vk.CreateSampler(b.device, &ci, nil, &b.sampler) == .SUCCESS
}

@(private)
make_pipeline_layout :: proc(b: ^Backend) -> bool {
	layout := b.desc_layout
	range := vk.PushConstantRange {
		stageFlags = {.VERTEX},
		offset     = 0,
		size       = size_of(Push),
	}
	ci := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &layout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &range,
	}
	return vk.CreatePipelineLayout(b.device, &ci, nil, &b.layout) == .SUCCESS
}

@(private)
make_module :: proc(b: ^Backend, code: []u32) -> vk.ShaderModule {
	ci := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code) * size_of(u32),
		pCode    = raw_data(code),
	}
	m: vk.ShaderModule
	vk.CreateShaderModule(b.device, &ci, nil, &m)
	return m
}

@(private)
make_pipeline :: proc(b: ^Backend) -> bool {
	vert := make_module(b, VERT_SPV)
	frag := make_module(b, FRAG_SPV)
	if vert == 0 || frag == 0 {
		return false
	}
	defer vk.DestroyShaderModule(b.device, vert, nil)
	defer vk.DestroyShaderModule(b.device, frag, nil)

	stages := [2]vk.PipelineShaderStageCreateInfo {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = vert,
			pName = "main",
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = frag,
			pName = "main",
		},
	}

	vin := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = len(VERTEX_BINDING),
		pVertexBindingDescriptions      = raw_data(VERTEX_BINDING[:]),
		vertexAttributeDescriptionCount = len(VERTEX_ATTRS),
		pVertexAttributeDescriptions    = raw_data(VERTEX_ATTRS[:]),
	}

	asm_ := vk.PipelineInputAssemblyStateCreateInfo {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}

	vps := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	rast := vk.PipelineRasterizationStateCreateInfo {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		cullMode    = {},
		frontFace   = .COUNTER_CLOCKWISE,
		lineWidth   = 1,
	}

	msaa := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = b.samples,
		minSampleShading     = 1,
	}

	blend := vk.PipelineColorBlendAttachmentState {
		blendEnable         = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
		alphaBlendOp        = .ADD,
		colorWriteMask      = {.R, .G, .B, .A},
	}
	cb := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &blend,
	}

	dyn := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = len(DYNAMIC_STATES),
		pDynamicStates    = raw_data(DYNAMIC_STATES[:]),
	}

	ci := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = len(stages),
		pStages             = raw_data(stages[:]),
		pVertexInputState   = &vin,
		pInputAssemblyState = &asm_,
		pViewportState      = &vps,
		pRasterizationState = &rast,
		pMultisampleState   = &msaa,
		pColorBlendState    = &cb,
		pDynamicState       = &dyn,
		layout              = b.layout,
		renderPass          = b.pass,
		subpass             = 0,
	}
	return vk.CreateGraphicsPipelines(b.device, 0, 1, &ci, nil, &b.pipeline) == .SUCCESS
}

@(private)
make_set :: proc(b: ^Backend, view: vk.ImageView) -> vk.DescriptorSet {
	if b.desc_left == 0 {
		append(&b.desc_pools, make_desc_pool(b))
		b.desc_left = DESC_POOL_SETS
	}

	layout := b.desc_layout
	ai := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = b.desc_pools[len(b.desc_pools) - 1],
		descriptorSetCount = 1,
		pSetLayouts        = &layout,
	}
	set: vk.DescriptorSet
	if vk.AllocateDescriptorSets(b.device, &ai, &set) != .SUCCESS {
		return 0
	}
	b.desc_left -= 1

	info := vk.DescriptorImageInfo {
		sampler     = b.sampler,
		imageView   = view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}
	w := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = set,
		dstBinding      = 0,
		descriptorCount = 1,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		pImageInfo      = &info,
	}
	vk.UpdateDescriptorSets(b.device, 1, &w, 0, nil)
	return set
}

@(private)
make_view :: proc(b: ^Backend, img: vk.Image, format: vk.Format) -> vk.ImageView {
	ci := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = img,
		viewType = .D2,
		format = format,
		subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	view: vk.ImageView
	vk.CreateImageView(b.device, &ci, nil, &view)
	return view
}

@(private)
make_raw_image :: proc(
	b: ^Backend,
	w, h: int,
	format: vk.Format,
	usage: vk.ImageUsageFlags,
	samples: vk.SampleCountFlags,
) -> (Image, bool) {
	out := Image {
		w      = w,
		h      = h,
		layout = .UNDEFINED,
	}
	ci := vk.ImageCreateInfo {
		sType         = .IMAGE_CREATE_INFO,
		imageType     = .D2,
		format        = format,
		extent        = {u32(w), u32(h), 1},
		mipLevels     = 1,
		arrayLayers   = 1,
		samples       = samples,
		tiling        = .OPTIMAL,
		usage         = usage,
		sharingMode   = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}
	if vk.CreateImage(b.device, &ci, nil, &out.img) != .SUCCESS {
		return {}, false
	}

	req: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(b.device, out.img, &req)
	idx, ok := find_memory_type(b, req.memoryTypeBits, {.DEVICE_LOCAL})
	if !ok {
		vk.DestroyImage(b.device, out.img, nil)
		return {}, false
	}

	ai := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = req.size,
		memoryTypeIndex = idx,
	}
	if vk.AllocateMemory(b.device, &ai, nil, &out.mem) != .SUCCESS {
		vk.DestroyImage(b.device, out.img, nil)
		return {}, false
	}
	vk.BindImageMemory(b.device, out.img, out.mem, 0)

	out.view = make_view(b, out.img, format)
	return out, true
}

@(private)
make_attachment :: proc(b: ^Backend, w, h: int) -> Image {
	img, _ := make_raw_image(b, w, h, b.format, {.COLOR_ATTACHMENT, .TRANSIENT_ATTACHMENT}, b.samples)
	return img
}

@(private)
make_image :: proc(b: ^Backend, w, h: int, pixels: []u8) -> Image {
	img, ok := make_raw_image(b, w, h, .R8G8B8A8_UNORM, {.TRANSFER_DST, .SAMPLED}, {._1})
	if !ok {
		return {}
	}
	img.set = make_set(b, img.view)
	if len(pixels) >= w * h * 4 {
		begin_upload(b)
		copy_pixels(b, &img, 0, 0, w, h, w, pixels)
		end_upload(b)
	}
	return img
}

@(private)
destroy_image :: proc(b: ^Backend, img: ^Image) {
	if img.view != 0 {
		vk.DestroyImageView(b.device, img.view, nil)
	}
	if img.img != 0 {
		vk.DestroyImage(b.device, img.img, nil)
	}
	if img.mem != 0 {
		vk.FreeMemory(b.device, img.mem, nil)
	}
	img^ = {}
}

@(private)
copy_pixels :: proc(b: ^Backend, img: ^Image, x, y, w, h, stride: int, pixels: []u8) {
	need := vk.DeviceSize(w * h * 4)
	if !grow_buffer(b, &b.staging, need, {.TRANSFER_SRC}) {
		return
	}

	dst := ([^]u8)(b.staging.ptr)
	for row in 0 ..< h {
		src := ((y + row) * stride + x) * 4
		copy(dst[row * w * 4:][:w * 4], pixels[src:][:w * 4])
	}

	barrier_image(b, img, .TRANSFER_DST_OPTIMAL)
	region := vk.BufferImageCopy {
		imageSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		imageOffset      = {i32(x), i32(y), 0},
		imageExtent      = {u32(w), u32(h), 1},
	}
	vk.CmdCopyBufferToImage(b.up_cmd, b.staging.buf, img.img, .TRANSFER_DST_OPTIMAL, 1, &region)
	barrier_image(b, img, .SHADER_READ_ONLY_OPTIMAL)
}

@(private)
barrier_image :: proc(b: ^Backend, img: ^Image, to: vk.ImageLayout) {
	src_stage, dst_stage: vk.PipelineStageFlags
	src_access, dst_access: vk.AccessFlags

	#partial switch img.layout {
	case .UNDEFINED:
		src_stage = {.TOP_OF_PIPE}
	case .SHADER_READ_ONLY_OPTIMAL:
		src_stage = {.FRAGMENT_SHADER}
		src_access = {.SHADER_READ}
	case .TRANSFER_DST_OPTIMAL:
		src_stage = {.TRANSFER}
		src_access = {.TRANSFER_WRITE}
	case:
		src_stage = {.TOP_OF_PIPE}
	}

	#partial switch to {
	case .TRANSFER_DST_OPTIMAL:
		dst_stage = {.TRANSFER}
		dst_access = {.TRANSFER_WRITE}
	case .SHADER_READ_ONLY_OPTIMAL:
		dst_stage = {.FRAGMENT_SHADER}
		dst_access = {.SHADER_READ}
	case:
		dst_stage = {.BOTTOM_OF_PIPE}
	}

	bar := vk.ImageMemoryBarrier {
		sType               = .IMAGE_MEMORY_BARRIER,
		srcAccessMask       = src_access,
		dstAccessMask       = dst_access,
		oldLayout           = img.layout,
		newLayout           = to,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image               = img.img,
		subresourceRange    = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	vk.CmdPipelineBarrier(b.up_cmd, src_stage, dst_stage, {}, 0, nil, 0, nil, 1, &bar)
	img.layout = to
}
