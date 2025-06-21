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
