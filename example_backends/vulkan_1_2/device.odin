package ui_vulkan_1_2

import "base:runtime"
import "core:fmt"
import vk "vendor:vulkan"
import "vendor:glfw"

API_VERSION :: vk.API_VERSION_1_2
API_NAME :: "1.2"

FRAMES_IN_FLIGHT :: 2
DESC_POOL_SETS :: 64

VALIDATION_LAYER :: "VK_LAYER_KHRONOS_validation"

Buffer :: struct {
	buf:  vk.Buffer,
	mem:  vk.DeviceMemory,
	size: vk.DeviceSize,
	ptr:  rawptr,
}

@(private)
fail :: proc(b: ^Backend, msg: string) -> bool {
	b.err = msg
	return false
}

@(private)
make_instance :: proc(b: ^Backend) -> bool {
	if !glfw.VulkanSupported() {
		return fail(b, "no Vulkan loader was found on this machine")
	}

	get_addr := glfw.GetInstanceProcAddress(nil, "vkGetInstanceProcAddr")
	if get_addr == nil {
		return fail(b, "the Vulkan loader did not provide vkGetInstanceProcAddr")
	}
	vk.load_proc_addresses_global(get_addr)
	if vk.CreateInstance == nil {
		return fail(b, "the Vulkan loader did not provide vkCreateInstance")
	}

	loader: u32 = vk.API_VERSION_1_0
	if vk.EnumerateInstanceVersion != nil {
		vk.EnumerateInstanceVersion(&loader)
	}
	if loader < API_VERSION {
		return fail(b, "the installed Vulkan loader is older than " + API_NAME)
	}

	app := vk.ApplicationInfo {
		sType            = .APPLICATION_INFO,
		pApplicationName = "loom",
		apiVersion       = API_VERSION,
	}

	exts := make([dynamic]cstring, context.temp_allocator)
	append(&exts, ..glfw.GetRequiredInstanceExtensions())

	layers := make([dynamic]cstring, context.temp_allocator)
	when ODIN_DEBUG {
		if has_layer(VALIDATION_LAYER) {
			append(&layers, cstring(VALIDATION_LAYER))
			append(&exts, cstring(vk.EXT_DEBUG_UTILS_EXTENSION_NAME))
		}
	}

	ci := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app,
		enabledExtensionCount   = u32(len(exts)),
		ppEnabledExtensionNames = raw_data(exts),
		enabledLayerCount       = u32(len(layers)),
		ppEnabledLayerNames     = raw_data(layers),
	}
	if vk.CreateInstance(&ci, nil, &b.instance) != .SUCCESS {
		return fail(b, "vkCreateInstance failed; this machine may not support Vulkan " + API_NAME)
	}
	vk.load_proc_addresses_instance(b.instance)

	when ODIN_DEBUG {
		if len(layers) > 0 {
			make_messenger(b)
		}
	}
	return true
}

@(private)
has_layer :: proc(want: string) -> bool {
	n: u32
	vk.EnumerateInstanceLayerProperties(&n, nil)
	if n == 0 {
		return false
	}
	props := make([]vk.LayerProperties, int(n), context.temp_allocator)
	vk.EnumerateInstanceLayerProperties(&n, raw_data(props))
	for &p in props {
		if name_of(p.layerName[:]) == want {
			return true
		}
	}
	return false
}

@(private)
name_of :: proc(buf: []u8) -> string {
	for c, i in buf {
		if c == 0 {
			return string(buf[:i])
		}
	}
	return string(buf)
}

@(private)
debug_cb :: proc "system" (
	severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	types: vk.DebugUtilsMessageTypeFlagsEXT,
	data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	user: rawptr,
) -> b32 {
	context = runtime.default_context()
	fmt.eprintfln("vulkan: %s", data.pMessage)
	return false
}

@(private)
make_messenger :: proc(b: ^Backend) {
	if vk.CreateDebugUtilsMessengerEXT == nil {
		return
	}
	ci := vk.DebugUtilsMessengerCreateInfoEXT {
		sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = {.WARNING, .ERROR},
		messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE},
		pfnUserCallback = debug_cb,
	}
	vk.CreateDebugUtilsMessengerEXT(b.instance, &ci, nil, &b.debug)
}

@(private)
has_device_ext :: proc(d: vk.PhysicalDevice, want: string) -> bool {
	n: u32
	vk.EnumerateDeviceExtensionProperties(d, nil, &n, nil)
	if n == 0 {
		return false
	}
	props := make([]vk.ExtensionProperties, int(n), context.temp_allocator)
	vk.EnumerateDeviceExtensionProperties(d, nil, &n, raw_data(props))
	for &p in props {
		if name_of(p.extensionName[:]) == want {
			return true
		}
	}
	return false
}

@(private)
pick_queue :: proc(d: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (u32, bool) {
	n: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(d, &n, nil)
	if n == 0 {
		return 0, false
	}
	props := make([]vk.QueueFamilyProperties, int(n), context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(d, &n, raw_data(props))

	for p, i in props {
		if .GRAPHICS not_in p.queueFlags {
			continue
		}
		ok: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(d, u32(i), surface, &ok)
		if ok {
			return u32(i), true
		}
	}
	return 0, false
}

@(private)
pick_device :: proc(b: ^Backend, surface: vk.SurfaceKHR) -> bool {
	n: u32
	vk.EnumeratePhysicalDevices(b.instance, &n, nil)
	if n == 0 {
		return fail(b, "no Vulkan physical device was found")
	}
	devs := make([]vk.PhysicalDevice, int(n), context.temp_allocator)
	vk.EnumeratePhysicalDevices(b.instance, &n, raw_data(devs))

	saw_version, saw_swapchain, saw_features := false, false, false
	best := -1
	for d in devs {
		props: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(d, &props)
		if props.apiVersion < API_VERSION {
			continue
		}
		saw_version = true
		if !has_device_ext(d, string(vk.KHR_SWAPCHAIN_EXTENSION_NAME)) {
			continue
		}
		saw_swapchain = true
		if !has_features(d) {
			continue
		}
		saw_features = true
		fam, ok := pick_queue(d, surface)
		if !ok {
			continue
		}

		score := 0
		#partial switch props.deviceType {
		case .DISCRETE_GPU:
			score = 2
		case .INTEGRATED_GPU:
			score = 1
		}
		if score > best {
			best, b.gpu, b.qfamily = score, d, fam
		}
	}

	switch {
	case !saw_version:
		return fail(b, "no physical device reports Vulkan " + API_NAME + " or newer")
	case !saw_swapchain:
		return fail(b, "no physical device supports VK_KHR_swapchain")
	case !saw_features:
		return fail(b, "no physical device supports the required Vulkan " + API_NAME + " features")
	case best < 0:
		return fail(b, "no queue family supports both graphics and presentation")
	}

	vk.GetPhysicalDeviceMemoryProperties(b.gpu, &b.mem_props)

	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(b.gpu, &props)
	b.samples = pick_samples(b.opts.msaa, props.limits.framebufferColorSampleCounts)
	return true
}

@(private)
has_features :: proc(d: vk.PhysicalDevice) -> bool {
	return true
}

@(rodata)
SAMPLE_CHOICES := [?]struct {
	n: int,
	f: vk.SampleCountFlag,
}{{8, ._8}, {4, ._4}, {2, ._2}}

@(private)
pick_samples :: proc(want: int, supported: vk.SampleCountFlags) -> vk.SampleCountFlags {
	if want <= 1 {
		return {._1}
	}
	for c in SAMPLE_CHOICES {
		if c.n <= want && c.f in supported {
			return {c.f}
		}
	}
	return {._1}
}

@(private)
make_device :: proc(b: ^Backend) -> bool {
	prio: f32 = 1
	qci := vk.DeviceQueueCreateInfo {
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = b.qfamily,
		queueCount       = 1,
		pQueuePriorities = &prio,
	}
	exts := [?]cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

	dci := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = 1,
		pQueueCreateInfos       = &qci,
		enabledExtensionCount   = len(exts),
		ppEnabledExtensionNames = raw_data(exts[:]),
	}
	if vk.CreateDevice(b.gpu, &dci, nil, &b.device) != .SUCCESS {
		return fail(b, "vkCreateDevice failed")
	}
	vk.load_proc_addresses_device(b.device)
	vk.GetDeviceQueue(b.device, b.qfamily, 0, &b.queue)
	return true
}

@(private)
find_memory_type :: proc(b: ^Backend, bits: u32, want: vk.MemoryPropertyFlags) -> (u32, bool) {
	for i in 0 ..< b.mem_props.memoryTypeCount {
		if bits & (1 << i) == 0 {
			continue
		}
		if want <= b.mem_props.memoryTypes[i].propertyFlags {
			return i, true
		}
	}
	return 0, false
}

@(private)
make_buffer :: proc(
	b: ^Backend,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	host: bool,
) -> (Buffer, bool) {
	out: Buffer
	ci := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}
	if vk.CreateBuffer(b.device, &ci, nil, &out.buf) != .SUCCESS {
		return {}, false
	}

	req: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(b.device, out.buf, &req)
	want: vk.MemoryPropertyFlags = host ? {.HOST_VISIBLE, .HOST_COHERENT} : {.DEVICE_LOCAL}
	idx, ok := find_memory_type(b, req.memoryTypeBits, want)
	if !ok {
		vk.DestroyBuffer(b.device, out.buf, nil)
		return {}, false
	}

	ai := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = req.size,
		memoryTypeIndex = idx,
	}
	if vk.AllocateMemory(b.device, &ai, nil, &out.mem) != .SUCCESS {
		vk.DestroyBuffer(b.device, out.buf, nil)
		return {}, false
	}
	vk.BindBufferMemory(b.device, out.buf, out.mem, 0)

	if host {
		vk.MapMemory(b.device, out.mem, 0, req.size, {}, &out.ptr)
	}
	out.size = size
	return out, true
}

@(private)
destroy_buffer :: proc(b: ^Backend, buf: ^Buffer) {
	if buf.ptr != nil {
		vk.UnmapMemory(b.device, buf.mem)
	}
	if buf.buf != 0 {
		vk.DestroyBuffer(b.device, buf.buf, nil)
	}
	if buf.mem != 0 {
		vk.FreeMemory(b.device, buf.mem, nil)
	}
	buf^ = {}
}

@(private)
grow_buffer :: proc(
	b: ^Backend,
	buf: ^Buffer,
	need: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
) -> bool {
	if buf.buf != 0 && buf.size >= need {
		return true
	}
	size := max(need, buf.size * 2, 4096)
	destroy_buffer(b, buf)
	out, ok := make_buffer(b, size, usage, true)
	if !ok {
		return false
	}
	buf^ = out
	return true
}

@(private)
make_desc_pool :: proc(b: ^Backend) -> vk.DescriptorPool {
	size := vk.DescriptorPoolSize {
		type            = .COMBINED_IMAGE_SAMPLER,
		descriptorCount = DESC_POOL_SETS,
	}
	ci := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = DESC_POOL_SETS,
		poolSizeCount = 1,
		pPoolSizes    = &size,
	}
	pool: vk.DescriptorPool
	vk.CreateDescriptorPool(b.device, &ci, nil, &pool)
	return pool
}

@(private)
begin_upload :: proc(b: ^Backend) {
	vk.ResetCommandBuffer(b.up_cmd, {})
	bi := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	vk.BeginCommandBuffer(b.up_cmd, &bi)
}

@(private)
end_upload :: proc(b: ^Backend) {
	vk.EndCommandBuffer(b.up_cmd)
	cmd := b.up_cmd
	si := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &cmd,
	}
	vk.ResetFences(b.device, 1, &b.up_fence)
	vk.QueueSubmit(b.queue, 1, &si, b.up_fence)
	vk.WaitForFences(b.device, 1, &b.up_fence, true, max(u64))
}
