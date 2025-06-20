package engine

import "base:runtime"

import "core:log"

import "vendor:glfw"

Window :: struct {
	handle: glfw.WindowHandle,
	width:  i32,
	height: i32,
	title:  cstring,

	initialised: bool,
}

@(private)
window: Window

window_create :: proc(
	width:  i32,
	height: i32,
	title:  cstring,
	allocator := context.allocator,
) {
	assert(!window.initialised)
	ensure(bool(glfw.Init()))
	
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, true)

	window = {
		handle      = glfw.CreateWindow(width, height, title, nil, nil),
		width       = width,
		height      = height,
		title       = title,
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
	assert(window.initialised)

	glfw.PollEvents()
	input_poll()
}

window_should_close :: proc() -> bool {
	assert(window.initialised)
	
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
	assert(window.initialised)
	
	return glfw.GetWindowSize(window.handle)
}

window_set_size :: proc(
	width:  i32,
	height: i32
) {
	assert(window.initialised)

	glfw.SetWindowSize(window.handle, width, height)
	window.width  = width
	window.height = height
}

@(private="file")
window_on_resize :: proc "c" (
	width:  i32,
	height: i32
) {
	window.width  = width
	window.height = height
}
