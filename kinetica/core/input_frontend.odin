package core

import "vendor:glfw"

Mouse_Mode :: enum(i32) {
	Unlocked = glfw.CURSOR_NORMAL,
	Locked   = glfw.CURSOR_DISABLED,
}

Button_State :: enum {
	Pressed,
	Held,
	Released,
	Up,
}

input_is_key_pressed :: proc(
	key: Keycode
) -> (
	pressed: bool
) {
	assert(input.initialised)

	return input.key_states[key] == .Pressed
}

input_is_key_held :: proc(
	key: Keycode
) -> (
	held: bool
) {
	assert(input.initialised)

	return input.key_states[key] == .Held
}

input_is_key_released :: proc(
	key: Keycode
) -> (
	released: bool
) {
	assert(input.initialised)

	return input.key_states[key] == .Released
}

input_is_key_up :: proc(
	key: Keycode
) -> (
	up: bool
) {
	assert(input.initialised)

	return input.key_states[key] == .Up
}

input_is_mouse_pressed :: proc(
	button: Mousecode
) -> (
	pressed: bool
) {
	assert(input.initialised)

	return input.mouse_states[button] == .Pressed
}

input_is_mouse_held :: proc(
	button: Mousecode
) -> (
	held: bool
) {
	assert(input.initialised)

	return input.mouse_states[button] == .Held
}

input_is_mouse_released :: proc(
	button: Mousecode
) -> (
	released: bool
) {
	assert(input.initialised)

	return input.mouse_states[button] == .Released
}

input_is_mouse_up :: proc(
	button: Mousecode
) -> (
	up: bool
) {
	assert(input.initialised)

	return input.mouse_states[button] == .Up
}

input_get_mouse_pos_f32 :: proc() -> (
	mouse_pos: [2]f32
) {
	assert(input.initialised)

	return {
		f32(input.mouse_pos.x),
		f32(input.mouse_pos.y)
	}
}

input_get_mouse_pos_f64 :: proc() -> (
	mouse_pos: [2]f64
) {
	assert(input.initialised)

	return input.mouse_pos
}

input_get_relative_mouse_pos_f32 :: proc() -> (
	relative_pos: [2]f32
) {
	assert(input.initialised)

	return {
		f32(input.rel_mouse_pos.x),
		f32(input.rel_mouse_pos.y),
	}
}

input_get_relative_mouse_pos_f64 :: proc() -> (
	relative_pos: [2]f64
) {
	assert(input.initialised)

	return input.rel_mouse_pos
}

input_set_mouse_mode :: proc(
	mode: Mouse_Mode
) {
	assert(input.initialised)

	glfw.SetInputMode(glfw_context.handle, glfw.CURSOR, i32(mode))
	input.mouse_mode = mode
}
