package ui_vulkan_1_3

import vk "vendor:vulkan"
import "vendor:glfw"

Frame :: struct {
	cmd:     vk.CommandBuffer,
	fence:   vk.Fence,
	acquire: vk.Semaphore,
	vbuf:    Buffer,
	ibuf:    Buffer,
}

Target :: struct {
	win:         glfw.WindowHandle,
	surface:     vk.SurfaceKHR,
	swapchain:   vk.SwapchainKHR,
	extent:      vk.Extent2D,
	images:      [dynamic]vk.Image,
	views:       [dynamic]vk.ImageView,
	release:     [dynamic]vk.Semaphore,
	image_fence: [dynamic]vk.Fence,
	ms:          Image,
	frames:      [FRAMES_IN_FLIGHT]Frame,
	frame:       u32,
	dirty:       bool,
}

@(private)
pick_format :: proc(b: ^Backend, surface: vk.SurfaceKHR) -> (vk.Format, vk.ColorSpaceKHR) {
	n: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(b.gpu, surface, &n, nil)
	if n == 0 {
		return .B8G8R8A8_UNORM, .SRGB_NONLINEAR
	}
	formats := make([]vk.SurfaceFormatKHR, int(n), context.temp_allocator)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(b.gpu, surface, &n, raw_data(formats))

	if b.format != .UNDEFINED {
		for f in formats {
			if f.format == b.format && f.colorSpace == b.color_space {
				return f.format, f.colorSpace
			}
		}
	}
	for want in ([?]vk.Format{.B8G8R8A8_UNORM, .R8G8B8A8_UNORM}) {
		for f in formats {
			if f.format == want && f.colorSpace == .SRGB_NONLINEAR {
				return f.format, f.colorSpace
			}
		}
	}
	return formats[0].format, formats[0].colorSpace
}

@(private)
pick_present_mode :: proc(b: ^Backend, surface: vk.SurfaceKHR) -> vk.PresentModeKHR {
	if !b.opts.no_vsync {
		return .FIFO
	}
	n: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(b.gpu, surface, &n, nil)
	if n == 0 {
		return .FIFO
	}
	modes := make([]vk.PresentModeKHR, int(n), context.temp_allocator)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(b.gpu, surface, &n, raw_data(modes))

	for want in ([?]vk.PresentModeKHR{.MAILBOX, .IMMEDIATE}) {
		for m in modes {
			if m == want {
				return m
			}
		}
	}
	return .FIFO
}

@(private)
make_target :: proc(b: ^Backend, t: ^Target, win: glfw.WindowHandle) -> bool {
	t.win = win
	t.images = make([dynamic]vk.Image, 0, 4)
	t.views = make([dynamic]vk.ImageView, 0, 4)
	t.release = make([dynamic]vk.Semaphore, 0, 4)
	t.image_fence = make([dynamic]vk.Fence, 0, 4)

	cmds: [FRAMES_IN_FLIGHT]vk.CommandBuffer
	ai := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = b.cmd_pool,
		level              = .PRIMARY,
		commandBufferCount = FRAMES_IN_FLIGHT,
	}
	if vk.AllocateCommandBuffers(b.device, &ai, raw_data(cmds[:])) != .SUCCESS {
		return false
	}

	fi := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	si := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	for i in 0 ..< FRAMES_IN_FLIGHT {
		f := &t.frames[i]
		f.cmd = cmds[i]
		vk.CreateFence(b.device, &fi, nil, &f.fence)
		vk.CreateSemaphore(b.device, &si, nil, &f.acquire)
	}
	return true
}

@(private)
destroy_target :: proc(b: ^Backend, t: ^Target) {
	destroy_swapchain(b, t)

	for i in 0 ..< FRAMES_IN_FLIGHT {
		f := &t.frames[i]
		if f.fence != 0 {
			vk.DestroyFence(b.device, f.fence, nil)
		}
		if f.acquire != 0 {
			vk.DestroySemaphore(b.device, f.acquire, nil)
		}
		vk.FreeCommandBuffers(b.device, b.cmd_pool, 1, &f.cmd)
		destroy_buffer(b, &f.vbuf)
		destroy_buffer(b, &f.ibuf)
	}

	delete(t.images)
	delete(t.views)
	delete(t.release)
	delete(t.image_fence)

	if t.surface != 0 {
		vk.DestroySurfaceKHR(b.instance, t.surface, nil)
	}
	t^ = {}
}

@(private)
destroy_swapchain :: proc(b: ^Backend, t: ^Target) {
	for v in t.views {
		vk.DestroyImageView(b.device, v, nil)
	}
	clear(&t.views)

	for s in t.release {
		vk.DestroySemaphore(b.device, s, nil)
	}
	clear(&t.release)

	clear(&t.images)
	clear(&t.image_fence)
	destroy_image(b, &t.ms)

	if t.swapchain != 0 {
		vk.DestroySwapchainKHR(b.device, t.swapchain, nil)
		t.swapchain = 0
	}
}

@(private)
ensure_target :: proc(b: ^Backend, t: ^Target) -> bool {
	caps: vk.SurfaceCapabilitiesKHR
	if vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(b.gpu, t.surface, &caps) != .SUCCESS {
		return false
	}

	ext := caps.currentExtent
	if ext.width == max(u32) {
		fw, fh := glfw.GetFramebufferSize(t.win)
		ext = {
			clamp(u32(fw), caps.minImageExtent.width, caps.maxImageExtent.width),
			clamp(u32(fh), caps.minImageExtent.height, caps.maxImageExtent.height),
		}
	}
	if ext.width == 0 || ext.height == 0 {
		return false
	}
	if t.swapchain != 0 && !t.dirty && t.extent == ext {
		return true
	}
	return rebuild_target(b, t, caps, ext)
}

@(private)
rebuild_target :: proc(
	b: ^Backend,
	t: ^Target,
	caps: vk.SurfaceCapabilitiesKHR,
	ext: vk.Extent2D,
) -> bool {
	vk.DeviceWaitIdle(b.device)

	old := t.swapchain
	t.swapchain = 0
	destroy_swapchain(b, t)

	count := caps.minImageCount + 1
	if caps.maxImageCount > 0 && count > caps.maxImageCount {
		count = caps.maxImageCount
	}

	format, space := pick_format(b, t.surface)
	if b.format == .UNDEFINED {
		b.format, b.color_space = format, space
	}

	ci := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = t.surface,
		minImageCount    = count,
		imageFormat      = b.format,
		imageColorSpace  = b.color_space,
		imageExtent      = ext,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		imageSharingMode = .EXCLUSIVE,
		preTransform     = caps.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = pick_present_mode(b, t.surface),
		clipped          = true,
		oldSwapchain     = old,
	}
	res := vk.CreateSwapchainKHR(b.device, &ci, nil, &t.swapchain)
	if old != 0 {
		vk.DestroySwapchainKHR(b.device, old, nil)
	}
	if res != .SUCCESS {
		t.swapchain = 0
		return false
	}
	t.extent = ext

	n: u32
	vk.GetSwapchainImagesKHR(b.device, t.swapchain, &n, nil)
	resize(&t.images, int(n))
	vk.GetSwapchainImagesKHR(b.device, t.swapchain, &n, raw_data(t.images))

	if b.samples != {._1} {
		t.ms = make_attachment(b, int(ext.width), int(ext.height))
	}

	si := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	for img in t.images {
		view := make_view(b, img, b.format)
		append(&t.views, view)

		sem: vk.Semaphore
		vk.CreateSemaphore(b.device, &si, nil, &sem)
		append(&t.release, sem)

		append(&t.image_fence, vk.Fence(0))
	}

	t.dirty = false
	return true
}

@(private)
acquire :: proc(b: ^Backend, t: ^Target, f: ^Frame, image: ^u32) -> bool {
	res := vk.AcquireNextImageKHR(b.device, t.swapchain, max(u64), f.acquire, 0, image)
	#partial switch res {
	case .SUCCESS:
	case .SUBOPTIMAL_KHR:
		t.dirty = true
	case .ERROR_OUT_OF_DATE_KHR:
		t.dirty = true
		return false
	case:
		t.dirty = true
		return false
	}

	prev := t.image_fence[image^]
	if prev != 0 && prev != f.fence {
		vk.WaitForFences(b.device, 1, &prev, true, max(u64))
	}
	t.image_fence[image^] = f.fence
	return true
}

@(private)
present :: proc(b: ^Backend, t: ^Target, image: u32) {
	sem := t.release[image]
	sc := t.swapchain
	idx := image
	pi := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &sem,
		swapchainCount     = 1,
		pSwapchains        = &sc,
		pImageIndices      = &idx,
	}
	res := vk.QueuePresentKHR(b.queue, &pi)
	if res == .ERROR_OUT_OF_DATE_KHR || res == .SUBOPTIMAL_KHR {
		t.dirty = true
	}
}
