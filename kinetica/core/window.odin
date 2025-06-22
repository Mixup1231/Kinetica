package core

import "base:runtime"

import "core:log"
import "core:mem"

import "vendor:glfw"
import vk "vendor:vulkan"

Window :: struct {
	handle:    glfw.WindowHandle,
	width:     i32,
	height:    i32,
	title:     cstring,
	allocator: mem.Allocator,

	initialised: bool,
}

@(private)
window: Window

window_create :: proc(
	width:       i32,
	height:      i32,
	title:       cstring,
	app_name:    cstring = "",
	app_version: u32     = 0,
	allocator := context.allocator,
) {
	context.allocator = allocator
	ensure(!window.initialised)
	ensure(bool(glfw.Init()))
	
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, true)

	window = {
		handle      = glfw.CreateWindow(width, height, title, nil, nil),
		width       = width,
		height      = height,
		title       = title,
		allocator   = allocator,
		initialised = true
	}	
	ensure(window.handle != nil)

	input_init()
	
	app_info: VK_Application_Info = {
		api_version = vk.MAKE_VERSION(1, 0, 0),
		app_name    = app_name,
		app_version = app_version,
		extensions  = {},
		layers      = {"VK_LAYER_KHRONOS_validation"},
		features    = nil,
	}

	device_attribtes: VK_Device_Attributes = {
		extensions    = {"VK_KHR_swapchain"},
		present_modes = { .FIFO } 
	}

	swapchain_attributes: VK_Swapchain_Attributes = {
		present_mode = .FIFO,
		extent       = {
			width  = u32(width),
			height = u32(height)
		},
		format       = {
			format     = .R8G8B8A8_SRGB,
			colorSpace = .SRGB_NONLINEAR, 
		},
		image_usage  = {
			.COLOR_ATTACHMENT,
			.TRANSFER_DST
		}
	}

	vulkan_init(app_info, device_attribtes, swapchain_attributes)
}

window_destroy :: proc() {
	ensure(window.initialised)

	input_destroy()
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
}

window_poll :: proc() {
	ensure(window.initialised)

	glfw.PollEvents()
	input_poll()
}

window_should_close :: proc() -> bool {
	ensure(window.initialised)
	
	return bool(glfw.WindowShouldClose(window.handle))
}

window_set_should_close :: proc(
	value: bool
) {
	ensure(window.initialised)

	glfw.SetWindowShouldClose(window.handle, b32(value))
}

window_get_size :: proc() -> (
 	width:  i32,
 	height: i32
) {
	ensure(window.initialised)
	
	return glfw.GetWindowSize(window.handle)
}

window_set_size :: proc(
	width:  i32,
	height: i32
) {
	ensure(window.initialised)

	glfw.SetWindowSize(window.handle, width, height)
	window.width  = width
	window.height = height
}

@(private="file")
window_on_resize :: proc "c" (
	width:  i32,
	height: i32
) {
	context = runtime.default_context()
	ensure(window.initialised)
	
	window.width  = width
	window.height = height
}
