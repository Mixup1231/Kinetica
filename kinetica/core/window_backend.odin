#+private
package core

import "base:runtime"

import "vendor:glfw"
import vk "vendor:vulkan"

Glfw_Context :: struct {
	handle:    glfw.WindowHandle,
	width:     i32,
	height:    i32,
	title:     cstring,

	initialised: bool,
}
glfw_context: Glfw_Context

window_on_resize :: proc "c" (
	handle: glfw.WindowHandle,
	width:  i32,
	height: i32
) {
	context = runtime.default_context()
	ensure(glfw_context.initialised)
	
	glfw_context.width  = width
	glfw_context.height = height
}
