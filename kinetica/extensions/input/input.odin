package input
import "base:runtime"
import "core:log"
import "core:math/bits"
import "vendor:glfw"

@(private)
input_ctx: Input_Context

@(private)
MAX_INPUT_KEYS :: 349 // From GLFW
@(private)
key_infos: [MAX_INPUT_KEYS]Key_Info

// Note(Jack): The current input system uses a map to assign key binds,
// this is used to reduce code complexity and gives the side effect of
// binding a key overriding the old bind. An array would likely be more
// performant here but I prefer this at time of writing

init :: proc(window: glfw.WindowHandle) {
	assert(window != nil)
	assert(!input_ctx.initialised)
	input_ctx.odin_ctx = context
	input_ctx.global_map.binds = make(map[Key]proc())
	input_ctx.global_map.toggles = make(map[Key]Toggle)
	glfw.SetKeyCallback(window, key_callback)
	input_ctx.initialised = true
}

@(require_results)
init_mapping_ctx :: proc(window: glfw.WindowHandle) -> Mapping_Context {
	assert(window != nil)
	assert(input_ctx.initialised)
	ctx := Mapping_Context {
		binds   = make(map[Key]proc()),
		toggles = make(map[Key]Toggle),
	}
	return ctx
}

bind_key :: proc {
	bind_key_global,
	bind_key_ctx,
}

bind_toggle :: proc {
	bind_toggle_global,
	bind_toggle_ctx,
}

bind_mapping_ctx :: proc(ctx: ^Mapping_Context) {
	input_ctx.current_map = ctx
}

is_key_down :: proc(key: Key) -> bool {
	return key_infos[key.code].isDown
}

destroy :: proc(contexts: ..^Mapping_Context) {
	assert(input_ctx.initialised)
	for ctx in contexts {
		delete(ctx.binds)
		delete(ctx.toggles)
	}
	delete(input_ctx.global_map.toggles)
	delete(input_ctx.global_map.binds)
	input_ctx.initialised = false
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
	if action != glfw.REPEAT do key_infos[key_code].isDown = !key_infos[key_code].isDown
	key := Key {
		code     = transmute(Key_Code)key_code,
		modifier = transmute(Key_Modifiers)mods,
		action   = transmute(Key_Action)action,
	}
	if key in input_ctx.current_map.binds {
		input_ctx.current_map.binds[key]()
		if key in input_ctx.current_map.toggles {
			if (input_ctx.current_map.binds[key] == input_ctx.current_map.toggles[key].first) {
				bind_key(input_ctx.current_map, key, input_ctx.current_map.toggles[key].second)
				return
			} else {
				bind_key(input_ctx.current_map, key, input_ctx.current_map.toggles[key].first)
				return
			}
		}
	}
	if key in input_ctx.global_map.binds {
		input_ctx.global_map.binds[key]()
		if key in input_ctx.global_map.toggles {
			if (input_ctx.global_map.binds[key] == input_ctx.global_map.toggles[key].first) {
				bind_key(key, input_ctx.global_map.toggles[key].second)
			} else {
				bind_key(key, input_ctx.global_map.toggles[key].first)
			}
		}
	}
}

@(private)
bind_key_global :: proc(key: Key, func: proc()) {
	input_ctx.global_map.binds[key] = func
}

@(private)
bind_toggle_global :: proc(key: Key, first: proc(), second: proc()) {
	toggle := Toggle{first, second}
	input_ctx.global_map.toggles[key] = toggle
	bind_key(key, first)
}

@(private)
bind_key_ctx :: proc(ctx: ^Mapping_Context, key: Key, func: proc()) {
	ctx.binds[key] = func
}

@(private)
bind_toggle_ctx :: proc(ctx: ^Mapping_Context, key: Key, first: proc(), second: proc()) {
	toggle := Toggle{first, second}
	ctx.toggles[key] = toggle
	bind_key_ctx(ctx, key, first)
}

