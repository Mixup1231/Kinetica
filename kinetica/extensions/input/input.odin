package input
import "base:runtime"
import "core:log"
import "core:math/bits"
import "vendor:glfw"

input_ctx: Input_Context

init :: proc(window: glfw.WindowHandle) {
	assert(window != nil)
	assert(!input_ctx.initialised)
	input_ctx.odin_ctx = context
	input_ctx.input_binds = make(map[Key]proc())
	input_ctx.input_toggles = make(map[Key]Toggle)
	glfw.SetKeyCallback(window, key_callback)
	input_ctx.initialised = true
}

@(private)
key_callback :: proc "c" (
	window: glfw.WindowHandle,
	key_code: i32,
	scan_code: i32,
	action: i32,
	mods: i32,
) {
	context = input_ctx.odin_ctx
	key := Key {
		code     = transmute(Key_Code)key_code,
		modifier = transmute(Key_Modifiers)mods,
		action   = transmute(Key_Action)action,
	}
	if key in input_ctx.input_binds {
		input_ctx.input_binds[key]()
		if key in input_ctx.input_toggles {
			if (input_ctx.input_binds[key] == input_ctx.input_toggles[key].first) {
				bind_key(key, input_ctx.input_toggles[key].second)
			} else {
				bind_key(key, input_ctx.input_toggles[key].first)
			}
		}
	}
}

destroy :: proc() {
	assert(input_ctx.initialised)
	delete(input_ctx.input_toggles)
	delete(input_ctx.input_binds)
	input_ctx.initialised = false
}

bind_key :: proc(key: Key, func: proc()) {
	input_ctx.input_binds[key] = func
}

bind_toggle :: proc(key: Key, first: proc(), second: proc()) {
	toggle := Toggle {
		first  = first,
		second = second,
	}
	input_ctx.input_toggles[key] = toggle
	bind_key(key, first)
}

