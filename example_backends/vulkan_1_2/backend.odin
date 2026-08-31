package ui_vulkan_1_2

import "core:c"
import vk "vendor:vulkan"
import "vendor:glfw"
import ui "../../loom"

MAX_FACES :: 32
DEFAULT_ARC_SEGMENTS :: 6
DEFAULT_ATLAS_SIZE :: 1024
DEFAULT_MSAA :: 4
MAX_SHADOW_STEPS :: 12

Options :: struct {
	arc_segments: int,
	atlas_size:   int,
	dpi:          f32,
	msaa:         int,
	no_vsync:     bool,
}

Win_State :: struct {
	keys_down:      ui.Key_Set,
	keys_pressed:   ui.Key_Set,
	mods:           ui.Mod_Set,
	mouse_down:     ui.Mouse_Set,
	mouse_pressed:  ui.Mouse_Set,
	mouse_released: ui.Mouse_Set,
	wheel:          ui.Vec2,
	text_buf:       [64]byte,
	text_out:       [64]byte,
	text_len:       int,
	inside:         bool,
}

Tex_Info :: struct {
	img:  Image,
	set:  vk.DescriptorSet,
	w, h: int,
}

Backend :: struct {
	win:         glfw.WindowHandle,
	opts:        Options,
	err:         string,

	instance:    vk.Instance,
	debug:       vk.DebugUtilsMessengerEXT,
	gpu:         vk.PhysicalDevice,
	device:      vk.Device,
	queue:       vk.Queue,
	qfamily:     u32,
	mem_props:   vk.PhysicalDeviceMemoryProperties,
	samples:     vk.SampleCountFlags,
	format:      vk.Format,
	color_space: vk.ColorSpaceKHR,

	cmd_pool:    vk.CommandPool,
	desc_layout: vk.DescriptorSetLayout,
	layout:      vk.PipelineLayout,
	pipeline:    vk.Pipeline,
	sampler:     vk.Sampler,
	pass:        vk.RenderPass,
	desc_pools:  [dynamic]vk.DescriptorPool,
	desc_left:   u32,

	up_cmd:      vk.CommandBuffer,
	up_fence:    vk.Fence,
	staging:     Buffer,

	main:        Target,
	target:      ^Target,

	verts:       [dynamic]Vertex,
	idxs:        [dynamic]u32,
	batches:     [dynamic]Batch,
	batch_set:   vk.DescriptorSet,
	batch_clip:  ui.Rect,
	batch_first: u32,
	clip:        [dynamic]ui.Rect,
	path_a:      [dynamic]ui.Vec2,
	path_b:      [dynamic]ui.Vec2,

	white:       Image,
	faces:       [MAX_FACES]Face,
	n_faces:     int,
	pages:       [dynamic]Page,
	glyphs:      map[Glyph_Key]Glyph,
	textures:    map[u32]Tex_Info,
	next_tex:    u32,

	wins:        map[glfw.WindowHandle]^Win_State,
	cursors:     [ui.Cursor]glfw.CursorHandle,
	cursor:      ui.Cursor,
	viewports:   map[ui.Viewport_Handle]^Vp,
	next_vp:     u64,

	dpi:         f32,
	view:        ui.Vec2,
	fb:          ui.Vec2,
	scale:       f32,
	clear:       ui.Color,
	time:        f64,
	clipboard:   string,
}

init :: proc(
	b: ^Backend,
	win: glfw.WindowHandle,
	opts: Options = {},
) -> (ui.Backend, bool) {
	b^ = {}
	b.win = win
	b.opts = opts
	if b.opts.arc_segments <= 0 {
		b.opts.arc_segments = DEFAULT_ARC_SEGMENTS
	}
	if b.opts.atlas_size <= 0 {
		b.opts.atlas_size = DEFAULT_ATLAS_SIZE
	}
	if b.opts.msaa == 0 {
		b.opts.msaa = DEFAULT_MSAA
	}

	if !make_instance(b) {
		return {}, false
	}
	if glfw.CreateWindowSurface(b.instance, win, nil, &b.main.surface) != .SUCCESS {
		return {}, fail(b, "glfwCreateWindowSurface failed")
	}
	if !pick_device(b, b.main.surface) {
		return {}, false
	}
	if !make_device(b) {
		return {}, false
	}

	b.format, b.color_space = pick_format(b, b.main.surface)

	if !make_render_pass(b) {
		return {}, fail(b, "vkCreateRenderPass failed")
	}
	if !make_desc_layout(b) {
		return {}, fail(b, "vkCreateDescriptorSetLayout failed")
	}
	if !make_sampler(b) {
		return {}, fail(b, "vkCreateSampler failed")
	}
	if !make_pipeline_layout(b) {
		return {}, fail(b, "vkCreatePipelineLayout failed")
	}
	if !make_pipeline(b) {
		return {}, fail(b, "vkCreateGraphicsPipelines failed")
	}

	pci := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = b.qfamily,
	}
	if vk.CreateCommandPool(b.device, &pci, nil, &b.cmd_pool) != .SUCCESS {
		return {}, fail(b, "vkCreateCommandPool failed")
	}

	b.desc_pools = make([dynamic]vk.DescriptorPool, 0, 2)
	append(&b.desc_pools, make_desc_pool(b))
	b.desc_left = DESC_POOL_SETS

	ai := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = b.cmd_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	if vk.AllocateCommandBuffers(b.device, &ai, &b.up_cmd) != .SUCCESS {
		return {}, fail(b, "could not allocate the upload command buffer")
	}
	fci := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
	}
	vk.CreateFence(b.device, &fci, nil, &b.up_fence)

	WHITE :: [4]u8{255, 255, 255, 255}
	white := WHITE
	b.white = make_image(b, 1, 1, white[:])
	if b.white.set == 0 {
		return {}, fail(b, "could not create the white texture")
	}

	b.verts = make([dynamic]Vertex, 0, 4096)
	b.idxs = make([dynamic]u32, 0, 8192)
	b.batches = make([dynamic]Batch, 0, 64)
	b.clip = make([dynamic]ui.Rect, 0, 16)
	b.path_a = make([dynamic]ui.Vec2, 0, 64)
	b.path_b = make([dynamic]ui.Vec2, 0, 64)
	b.pages = make([dynamic]Page, 0, 2)
	b.glyphs = make(map[Glyph_Key]Glyph, 512)
	b.textures = make(map[u32]Tex_Info, 8)
	b.wins = make(map[glfw.WindowHandle]^Win_State, 4)
	b.viewports = make(map[ui.Viewport_Handle]^Vp, 4)

	b.faces[0] = {
		ascent   = 0.8,
		descent  = -0.2,
		line_gap = 0,
	}
	b.n_faces = 1

	SHAPES := [ui.Cursor]c.int {
		.Default     = glfw.ARROW_CURSOR,
		.Pointer     = glfw.POINTING_HAND_CURSOR,
		.Text        = glfw.IBEAM_CURSOR,
		.Resize_H    = glfw.RESIZE_EW_CURSOR,
		.Resize_V    = glfw.RESIZE_NS_CURSOR,
		.Grab        = glfw.POINTING_HAND_CURSOR,
		.Grabbing    = glfw.RESIZE_ALL_CURSOR,
		.Not_Allowed = glfw.NOT_ALLOWED_CURSOR,
	}
	for shape, cur in SHAPES {
		b.cursors[cur] = glfw.CreateStandardCursor(shape)
	}

	if !make_target(b, &b.main, win) {
		return {}, fail(b, "could not create the swapchain resources")
	}
	b.target = &b.main

	adopt_window(b, win)
	b.dpi = window_dpi(b, win)
	b.time = glfw.GetTime()

	return ui.Backend {
			measure_run = measure_run,
			font_metrics = font_metrics,
			set_cursor = set_cursor,
			clipboard_get = clipboard_get,
			clipboard_set = clipboard_set,
			user = b,
			viewports = viewport_ops(),
		},
		true
}

destroy :: proc(b: ^Backend) {
	if b.device != nil {
		vk.DeviceWaitIdle(b.device)
	}

	for h, v in b.viewports {
		destroy_target(b, &v.target)
		glfw.DestroyWindow(v.win)
		free(v)
		delete_key(&b.viewports, h)
	}
	delete(b.viewports)

	for _, w in b.wins {
		free(w)
	}
	delete(b.wins)

	for cur in ui.Cursor {
		if b.cursors[cur] != nil {
			glfw.DestroyCursor(b.cursors[cur])
		}
	}

	if b.device != nil {
		destroy_target(b, &b.main)

		for &p in b.pages {
			destroy_image(b, &p.img)
			delete(p.pixels)
		}
		for _, &t in b.textures {
			destroy_image(b, &t.img)
		}
		destroy_image(b, &b.white)
		destroy_buffer(b, &b.staging)

		if b.up_fence != 0 {
			vk.DestroyFence(b.device, b.up_fence, nil)
		}
		for pool in b.desc_pools {
			vk.DestroyDescriptorPool(b.device, pool, nil)
		}
		if b.cmd_pool != 0 {
			vk.DestroyCommandPool(b.device, b.cmd_pool, nil)
		}
		if b.pipeline != 0 {
			vk.DestroyPipeline(b.device, b.pipeline, nil)
		}
		if b.layout != 0 {
			vk.DestroyPipelineLayout(b.device, b.layout, nil)
		}
		if b.sampler != 0 {
			vk.DestroySampler(b.device, b.sampler, nil)
		}
		if b.desc_layout != 0 {
			vk.DestroyDescriptorSetLayout(b.device, b.desc_layout, nil)
		}
		if b.pass != 0 {
			vk.DestroyRenderPass(b.device, b.pass, nil)
		}
		vk.DestroyDevice(b.device, nil)
	}

	delete(b.pages)
	delete(b.glyphs)
	delete(b.desc_pools)

	for i in 0 ..< b.n_faces {
		if b.faces[i].owned {
			delete(b.faces[i].data)
		}
	}

	if b.instance != nil {
		if b.debug != 0 && vk.DestroyDebugUtilsMessengerEXT != nil {
			vk.DestroyDebugUtilsMessengerEXT(b.instance, b.debug, nil)
		}
		vk.DestroyInstance(b.instance, nil)
	}

	delete(b.verts)
	delete(b.idxs)
	delete(b.batches)
	delete(b.clip)
	delete(b.path_a)
	delete(b.path_b)
	delete(b.textures)
	b^ = {}
}

register_texture :: proc(b: ^Backend, view: vk.ImageView, w, h: int) -> ui.Texture {
	set := make_set(b, view)
	if set == 0 {
		return 0
	}
	b.next_tex += 1
	b.textures[b.next_tex] = {
		set = set,
		w   = w,
		h   = h,
	}
	return ui.Texture(b.next_tex)
}

load_texture :: proc(b: ^Backend, w, h: int, rgba: []u8) -> ui.Texture {
	assert(len(rgba) >= w * h * 4, "ui_vulkan_1_2: pixel buffer is smaller than the texture")
	img := make_image(b, w, h, rgba)
	if img.set == 0 {
		return 0
	}
	b.next_tex += 1
	b.textures[b.next_tex] = {
		img = img,
		set = img.set,
		w   = w,
		h   = h,
	}
	return ui.Texture(b.next_tex)
}

set_cursor :: proc(cur: ui.Cursor, user: rawptr) {
	b := (^Backend)(user)
	if b.cursor == cur {
		return
	}
	b.cursor = cur
	glfw.SetCursor(b.win, b.cursors[cur])
	for _, v in b.viewports {
		glfw.SetCursor(v.win, b.cursors[cur])
	}
}

clipboard_get :: proc(user: rawptr) -> string {
	b := (^Backend)(user)
	b.clipboard = glfw.GetClipboardString(b.win)
	return b.clipboard
}

clipboard_set :: proc(text: string, user: rawptr) {
	b := (^Backend)(user)
	glfw.SetClipboardString(b.win, cstr(text))
}

@(private)
cstr :: proc(s: string) -> cstring {
	buf := make([]byte, len(s) + 1, context.temp_allocator)
	copy(buf, s)
	buf[len(s)] = 0
	return cstring(raw_data(buf))
}

@(private)
window_dpi :: proc(b: ^Backend, win: glfw.WindowHandle) -> f32 {
	if b.opts.dpi > 0 {
		return b.opts.dpi
	}
	fw, _ := glfw.GetFramebufferSize(win)
	ww, _ := glfw.GetWindowSize(win)
	if ww > 0 && fw > 0 {
		return f32(fw) / f32(ww)
	}
	sx, _ := glfw.GetWindowContentScale(win)
	return sx > 0 ? sx : 1
}
