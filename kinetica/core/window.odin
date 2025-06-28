package core

import "base:runtime"

import "core:log"
import "core:mem"

import "vendor:glfw"
import vk "vendor:vulkan"

@(private)
Glfw_Context :: struct {
	handle:    glfw.WindowHandle,
	width:     i32,
	height:    i32,
	title:     cstring,

	initialised: bool,
}

@(private)
glfw_context: Glfw_Context

window_create :: proc(
	width:       i32,
	height:      i32,
	title:       cstring,
	app_name:    cstring = "",
	app_version: u32     = 0,
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
		initialised = true
	}	
	ensure(glfw_context.handle != nil)

	input_init()
	
	app_info: Application_Info = {
		api_version = vk.API_VERSION_1_3,
		app_name    = app_name,
		app_version = app_version,
		extensions  = {},
		layers      = {"VK_LAYER_KHRONOS_validation"},
		features    = nil,
	}

	dynamic_rendering_feature: vk.PhysicalDeviceDynamicRenderingFeaturesKHR = {
		sType            = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,
		dynamicRendering = true,
	}

	device_attribtes: Device_Attributes = {
		features      = &dynamic_rendering_feature,
		present_modes = { .FIFO },
		extensions    = {
			vk.KHR_SWAPCHAIN_EXTENSION_NAME,
			// vk.KHR_DYNAMIC_RENDERING_EXTENSION_NAME,
			// vk.KHR_DEPTH_STENCIL_RESOLVE_EXTENSION_NAME
		}
	}

	swapchain_attributes: Swapchain_Attributes = {
		present_mode = .FIFO,
		extent = {
			width  = u32(width),
			height = u32(height)
		},
		format = {
			format     = .R8G8B8A8_SRGB,
			colorSpace = .SRGB_NONLINEAR,
		},
		image_usage = {
			.COLOR_ATTACHMENT,
			.TRANSFER_DST
		}
	}

	vulkan_init(app_info, device_attribtes, swapchain_attributes)
}

window_destroy :: proc() {
	ensure(glfw_context.initialised)

	input_destroy()
	vulkan_destroy()
	glfw.DestroyWindow(glfw_context.handle)
	glfw.Terminate()
}

window_poll :: proc() {
	ensure(glfw_context.initialised)

	glfw.PollEvents()
	input_poll()
}

window_should_close :: proc() -> bool {
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
	
	return glfw.GetWindowSize(glfw_context.handle)
}

window_set_size :: proc(
	width:  i32,
	height: i32
) {
	ensure(glfw_context.initialised)

	glfw.SetWindowSize(glfw_context.handle, width, height)
	glfw_context.width  = width
	glfw_context.height = height
}

window_get_framebuffer_size :: proc() -> (
	width:  i32,
	height: i32,
) {
	ensure(glfw_context.initialised)

	return glfw.GetFramebufferSize(glfw_context.handle)
}

@(private="file")
window_on_resize :: proc "c" (
	width:  i32,
	height: i32
) {
	context = runtime.default_context()
	ensure(glfw_context.initialised)
	
	glfw_context.width  = width
	glfw_context.height = height
}
