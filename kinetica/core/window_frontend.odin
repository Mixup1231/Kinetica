package core

import "vendor:glfw"
import vk "vendor:vulkan"

window_create :: proc(
	width:       i32,
	height:      i32,
	title:       cstring,
	allocator := context.allocator,
) {
	context.allocator = allocator
	ensure(!glfw_context.initialised)
	ensure(bool(glfw.Init()))

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, true)

	glfw_context = {
		handle      = glfw.CreateWindow(width, height, title, nil, nil),
		width       = width,
		height      = height,
		title       = title,
		initialised = true,
	}
	ensure(glfw_context.handle != nil)

	glfw.SetWindowSizeCallback(glfw_context.handle, window_on_resize)

	input_init()

	layers: []cstring
	when VALIDATION_LAYERS do layers = {"VK_LAYER_KHRONOS_validation"}

	app_info: VK_Application_Info = {
		api_version = vk.API_VERSION_1_3,
		extensions  = {},
		layers      = layers,
		features    = nil,
	}

	dynamic_rendering_feature: vk.PhysicalDeviceDynamicRenderingFeaturesKHR = {
		sType            = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,
		dynamicRendering = true,
	}

	device_attribtes: VK_Device_Attributes = {
		features      = &dynamic_rendering_feature,
		present_modes = {.FIFO},
		extensions    = {vk.KHR_SWAPCHAIN_EXTENSION_NAME},
	}

	swapchain_attributes: VK_Swapchain_Attributes = {
		present_mode = .FIFO,
		extent = {
			width  = u32(width),
			height = u32(height)
		},
		format = {
			format     = .R8G8B8A8_SRGB,
			colorSpace = .SRGB_NONLINEAR
		},
		image_usage = {
			.COLOR_ATTACHMENT,
			.TRANSFER_DST
		},
	}

	vk_init(app_info, device_attribtes, swapchain_attributes)
}

window_destroy :: proc() {
	ensure(glfw_context.initialised)

	input_destroy()
	vk_destroy()
	glfw.DestroyWindow(glfw_context.handle)
	glfw.Terminate()
}

window_poll :: proc() {
	ensure(glfw_context.initialised)

	glfw.PollEvents()
	input_poll()
}

window_should_close :: proc() -> (
	should_close: bool
) {
	ensure(glfw_context.initialised)

	return bool(glfw.WindowShouldClose(glfw_context.handle))
}

window_set_should_close :: proc(
	value: bool
) {
	ensure(glfw_context.initialised)

	glfw.SetWindowShouldClose(glfw_context.handle, b32(value))
}

window_get_size :: proc() -> (
	width:  i32,
	height: i32
) {
	ensure(glfw_context.initialised)

	return glfw_context.width, glfw_context.height
}

window_set_size :: proc(
	width:  i32,
	height: i32
) {
	ensure(glfw_context.initialised)

	glfw.SetWindowSize(glfw_context.handle, width, height)
	glfw_context.width, glfw_context.height = width, height
}

window_get_framebuffer_size :: proc() -> (
	width:  i32,
	height: i32
) {
	ensure(glfw_context.initialised)

	return glfw.GetFramebufferSize(glfw_context.handle)
}

window_wait_events :: proc() {
	ensure(glfw_context.initialised)

	glfw.WaitEvents()
}

window_get_handle :: proc() -> (
	handle: glfw.WindowHandle
) {
	return glfw_context.handle
}
