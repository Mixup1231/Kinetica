#+private
package core

import "base:runtime"

import "vendor:glfw"

Input :: struct {
	key_states:      map[Keycode]Button_State,
	mouse_states:    map[Mousecode]Button_State,
	mouse_pos:       [2]f64,
	rel_mouse_pos:   [2]f64,
	mouse_mode:      Mouse_Mode,

	initialised: bool,
}
input: Input

input_init :: proc(
	allocator := context.allocator
) {
	context.allocator = allocator
	ensure(glfw_context.initialised)
	ensure(!input.initialised)

	input = {
		key_states    = make(map[Keycode]Button_State),
		mouse_states  = make(map[Mousecode]Button_State),
		mouse_mode    = .Unlocked,
		initialised   = true
	}

	for key in Keycode do input.key_states[key] = .Up
	for button in Mousecode do input.mouse_states[button] = .Up
}

input_destroy :: proc() {
	ensure(input.initialised)

	delete(input.key_states)
	delete(input.mouse_states)
}

input_poll :: proc() {
	ensure(glfw_context.initialised)
	ensure(input.initialised)

	// keyboard
	for key in Keycode {
		state := &input.key_states[key]
		new_state := glfw.GetKey(glfw_context.handle, i32(key))
		
		if new_state == glfw.PRESS {
			switch (state^) {
			case .Pressed:  state^ = .Held
			case .Held:     state^ = .Held
			case .Released: state^ = .Pressed
			case .Up:       state^ = .Pressed
			}
		} else {
			switch (state^) {
			case .Pressed:  state^ = .Released
			case .Held:     state^ = .Released
			case .Released: state^ = .Up
			case .Up:       state^ = .Up
			}
		}
	}

	// mouse buttons
	for button in Mousecode {
		state := &input.mouse_states[button]
		new_state := glfw.GetMouseButton(glfw_context.handle, i32(button))
		
		if new_state == glfw.PRESS {
			switch (state^) {
			case .Pressed:  state^ = .Held
			case .Held:     state^ = .Held
			case .Released: state^ = .Pressed
			case .Up:       state^ = .Pressed
			}
		} else {
			switch (state^) {
			case .Pressed:  state^ = .Released
			case .Held:     state^ = .Released
			case .Released: state^ = .Up
			case .Up:       state^ = .Up
			}
		}
	}

	// mouse pos
	x, y := glfw.GetCursorPos(glfw_context.handle)
	prev_mouse_pos := input.mouse_pos
	
	input.mouse_pos     = {x, y}
	input.rel_mouse_pos = input.mouse_pos - prev_mouse_pos

	// NOTE(Mitchell): recentre mouse when moved (while locked) to keep it relative to the window centre
	if input.mouse_mode == .Locked do glfw.SetCursorPos(glfw_context.handle,f64(glfw_context.width) / 2, f64(glfw_context.height) / 2)
}
