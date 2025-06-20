package engine

import "core:log"

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

Input :: struct {
	key_states:    map[Keycode]Button_State,
	mouse_states:  map[Mousecode]Button_State,
	mouse_pos:     [2]f64,
	rel_mouse_pos: [2]f64,
	mouse_mode:    Mouse_Mode,

	initialised: bool,
}

@(private)
input: Input

@(private)
input_init :: proc(
	allocator := context.allocator
) {
	ensure(window.initialised)
	ensure(!input.initialised)

	context.allocator = allocator
	input = {
		key_states   = make(map[Keycode]Button_State),
		mouse_states = make(map[Mousecode]Button_State),
		mouse_mode   = .Unlocked,
		initialised  = true
	}

	for key in Keycode {
		input.key_states[key] = .Up
	}
	
	for button in Mousecode {
		input.mouse_states[button] = .Up
	}	
}

@(private)
input_destroy :: proc() {
	ensure(input.initialised)

	delete(input.key_states)
	delete(input.mouse_states)
}

@(private)
input_poll :: proc() {
	assert(window.initialised)
	assert(input.initialised)

	// keyboard
	for key in Keycode {
		state := &input.key_states[key]
		new_state := glfw.GetKey(window.handle, i32(key))
		
		if new_state == glfw.PRESS {
			switch (state^) {
			case .Pressed:
				state^ = .Held
			case .Held:
				state^ = .Held
			case .Released:
				state^ = .Pressed
			case .Up:
				state^ = .Pressed
			}
		} else {
			switch (state^) {
			case .Pressed:
				state^ = .Released
			case .Held:
				state^ = .Released
			case .Released:
				state^ = .Up
			case .Up:
				state^ = .Released
			}
		}
	}

	// mouse buttons
	for button in Mousecode {
		state := &input.mouse_states[button]
		new_state := glfw.GetMouseButton(window.handle, i32(button))
		
		if new_state == glfw.PRESS {
			switch (state^) {
			case .Pressed:
				state^ = .Held
			case .Held:
				state^ = .Held
			case .Released:
				state^ = .Pressed
			case .Up:
				state^ = .Pressed
			}
		} else {
			switch (state^) {
			case .Pressed:
				state^ = .Released
			case .Held:
				state^ = .Released
			case .Released:
				state^ = .Up
			case .Up:
				state^ = .Released
			}
		}
	}

	// mouse pos
	x, y                := glfw.GetCursorPos(window.handle)
	prev_mouse_pos      := input.mouse_pos	
	input.mouse_pos      = {x, y}
	input.rel_mouse_pos  = input.mouse_pos - prev_mouse_pos

	// NOTE(Mitchell): recentre mouse when moved (while locked) to keep it relative to the window centre
	if input.mouse_mode == .Locked {
		glfw.SetCursorPos(
			window.handle,
			f64(window.width)  / 2,
			f64(window.height) / 2
		)
	}
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

	glfw.SetInputMode(window.handle, glfw.CURSOR, i32(mode))
	input.mouse_mode = mode
}
