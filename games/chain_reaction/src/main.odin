package main

import "core:os"
import "core:fmt"
import "core:log"
import "core:time"
import la "core:math/linalg"
import oxr "../dependencies/openxr_odin/openxr"

import "../../../kinetica/core"
import "../engine"
import "../engine/vr"

import vk "vendor:vulkan"
	
main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)
	
	core.window_create(800, 600, "Oh my Gourd!")
	defer core.window_destroy()

	vk_info := core.vk_info_get()
	vr.init(vk_info)
	defer vr.destroy()

	is_valid: bool
	images_info: vr.Swapchain_Images_Info

	for !is_valid {
		vr.event_poll(vk_info)
		images_info, is_valid = vr.get_swapchain_images_info()
		time.sleep(1 * time.Millisecond)
	}	
	
	core.input_set_mouse_mode(.Locked)

	engine.resource_manager_init()
	defer engine.resource_manager_destory()

	engine.renderer_init()
	defer engine.renderer_destroy()
	
	engine.renderer_init_vr({
		image_count = images_info.count,
		extent = images_info.extent,
		format = vk.Format(images_info.format),
	})

	car_mesh := engine.resource_manager_load_mesh("games/chain_reaction/assets/models/GDC_Scene09-07-25.obj", {})
	defer engine.resource_manager_destroy_mesh(car_mesh)	

	scene := engine.scene_create()
	defer engine.scene_destroy(&scene)

	scene.ambient_strength = 0
	scene.ambient_color = {1, 1, 1}	
	
	one, one_struct := engine.scene_insert_entity(&scene)
	transform := core.transform_create()
	// core.transform_rotate(&transform, {0, 1, 0}, -la.PI / 4)
	engine.scene_register_mesh_component(&scene, one, car_mesh, transform)

	_, light := engine.scene_insert_point_light(&scene)
	light.color = {0.3, 0.3, 0.8, 1}
	light.position = {0, 4, 0, 1}
	
	// create pumpkin
	pumpkin_top_mesh := engine.resource_manager_load_mesh("games/chain_reaction/assets/models/pumpkin-top.obj", {})
	defer engine.resource_manager_destroy_mesh(pumpkin_top_mesh)	
	pumpkin_bot_mesh := engine.resource_manager_load_mesh("games/chain_reaction/assets/models/pumpkin-bot.obj", {})
	defer engine.resource_manager_destroy_mesh(pumpkin_bot_mesh)	

	init_input()
	
	fs: bool
	dt, pixel_size, max_pixel_size: f32 = 0, 4, 8
	start, end: time.Tick
	axis: [3]f32 = {1, 0, 0}
	camera: la.Quaternionf32
	created: bool
	for !core.window_should_close() {
		core.window_poll()
		
		if core.input_is_key_pressed(.Key_Escape) do core.window_set_should_close(true)

		if core.input_is_key_pressed(.Key_I) {
			fs = !fs
			if fs {
				core.window_go_fullscreen()
			} else {
				core.window_go_windowed(800, 600)
			}
		}

		if core.input_is_key_pressed(.Key_N) {
			pixel_size = f32(int(pixel_size + 1) % int(max_pixel_size))
			engine.renderer_set_pixelation(pixel_size + 1)
		}

		dt = f32(time.duration_seconds(time.tick_diff(start, end)))
		start = time.tick_now()
		app_time += dt

		if !created && app_time > 2 {
			for i in 0..<20 {
				create_pumpkin(&scene, pumpkin_top_mesh, pumpkin_bot_mesh)
			}
			created = true
		}
		
		engine.scene_update_entities(&scene, dt)
		engine.scene_update_physics_entities(&scene, dt)


		if get_input() {
			log.info("Pressed")
			destroy_pumpkin(&scene, &camera)
		}
		if core.input_is_key_pressed(.Key_X) {
			axis = {1, 0, 0}
		}
		if core.input_is_key_pressed(.Key_Y) {
			axis = {0, 1, 0}
		}
		if core.input_is_key_pressed(.Key_Z) {
			axis = {0, 0, 1}
		}
		if core.input_is_key_held(.Key_K) {
			core.transform_rotate(&one_struct.transform, axis, la.to_radians(f32(1)))
		}
		if core.input_is_key_held(.Key_J) {
			core.transform_rotate(&one_struct.transform, axis, la.to_radians(f32(-1)))
		}
		if core.input_is_key_pressed(.Key_P) {
		}
		if core.input_is_key_pressed(.Key_O) {
			for i in 0..<20 {
				create_pumpkin(&scene, pumpkin_top_mesh, pumpkin_bot_mesh)
			}
		}
		if core.input_is_key_pressed(.Key_H) {
			hot_reload_1 += 0.1
			if hot_reload_1 > 1 {
				hot_reload_1 = 0
			}
		}
		if core.input_is_key_pressed(.Key_G) {
			hot_reload_2 += 0.1
			if hot_reload_2 > 1 {
				hot_reload_2 = 0
			}
		}

		should_render := vr.event_poll(vk_info)
		if should_render {
			frame_data := vr.begin_frame()
			if !frame_data.frame_state.shouldRender {
				vr.end_frame(&frame_data)
				end = time.tick_now()
				continue
			}
			
			for i in 0..<frame_data.submit_count {
				view  := &frame_data.views[i]
				view.pose.position.y += 5
				image := vr.acquire_next_swapchain_image(i)
				
				camera = quaternion(real = view.pose.orientation.w, imag = view.pose.orientation.x, jmag = view.pose.orientation.y, kmag = view.pose.orientation.z)
				render_data: engine.VR_Render_Data = {
					image_handle = image.handle,
					image_view   = image.view,
					image_index  = image.index,
					camera       = {
						position = {view.pose.position.x, view.pose.position.y, view.pose.position.z},
						projection = vr.get_view_projection(&view.fov, 0.05, 100, &view.pose)
					}
				}
				engine.renderer_render_scene_vr(&scene, &render_data)
				vr.release_swapchain_image(i)
			}
			vr.end_frame(&frame_data)
		}
		end = time.tick_now()

		
		check_pumpkin_collisions(&scene, &pumpkin_top_mesh, &pumpkin_bot_mesh)
	}
}

import "core:math/rand"
import "core:math"
create_pumpkin :: proc(scene: ^engine.Scene, pumpkin_top_mesh: engine.Mesh, pumpkin_bot_mesh: engine.Mesh, spawn_pos := [3]f32{0, 0, 0}) {
	range : f32 = 30
	spawn: [3]f32
	if spawn_pos == {0,0,0} {
		spawn = generate_spawn_pos(range)
	} else {
		spawn = spawn_pos
	}
	top, e1 := engine.scene_insert_entity(scene)
	e1.tag = .Pumpkin
	transform := core.transform_create()
	core.transform_translate(&transform, {spawn.x, 1.5  + (math.abs(spawn.x) + math.abs(spawn.z))/f32(range), spawn.z})
	core.transform_look_at(&transform, {0, 2, 0})
	core.transform_rotate(&transform, {1, 0, 0}, la.PI)
	engine.scene_register_mesh_component(scene, top, pumpkin_top_mesh, transform)
	engine.scene_register_physics_component(scene, top, {})
	add_pumpkin_animation(scene, top)
	bot, e2 := engine.scene_insert_entity(scene)
	e2.tag = .Pumpkin
	transform = core.transform_create()
	core.transform_translate(&transform, {spawn.x, 1.5 + (math.abs(spawn.x) + math.abs(spawn.z))/f32(range), spawn.z})
	core.transform_look_at(&transform, {0, 2, 0})
	core.transform_rotate(&transform, {1, 0, 0}, la.PI)
	engine.scene_register_mesh_component(scene, bot, pumpkin_bot_mesh, transform)
	engine.scene_register_physics_component(scene, bot, {})
	e1.couple = e2
	e2.couple = e1
	log.info("Pumpkin with ids:", top, bot)
	return
}

generate_spawn_pos :: proc(range: f32) -> [3]f32 {
	spawn_x, spawn_z : f32
	spawn_x = (rand.float32() - 0.5) * f32(range)
	spawn_z = (rand.float32() - 0.5) * f32(range)

	if math.abs(spawn_x) < 5 && math.abs(spawn_z) < 5 {
		return generate_spawn_pos(range)
	}
	return [3]f32{spawn_x, 0, spawn_z}
}

pumpkin_update :: proc(dt: f32, pumpkin: ^engine.Entity) {
	return
}

@(private = "file")
app_time : f32 = 1
hot_reload_1 : f32 = 0
hot_reload_2 : f32 = 0
move_pumpkin_head :: proc(ts: f32, pumpkin : ^engine.Entity) {
	pumpkin_forward_vec := -pumpkin.transform.position
	core.transform_rotate(&pumpkin.transform, {0, 0, -1}, pumpkin_move_function(ts, app_time, {2, 6}, {0.2, 0.9}))
}

pumpkin_move_function :: proc(ts: f32, app_time: f32, periods: [2]f32, amplitudes: [2]f32) -> f32 {
	return ts * (amplitudes[0] * f32(la.sin(periods[0]  * app_time)) + (amplitudes[1] * f32(la.sin(periods[1] * app_time))))
}

add_pumpkin_animation :: proc(scene: ^engine.Scene, pumpkin_head: engine.Entity_ID) {
	script := engine.Script {
		update = move_pumpkin_head,
		fixed_update = move_pumpkin_head,
	}
	engine.scene_register_script_component(scene, pumpkin_head, script)
}

destroy_pumpkin :: proc(scene: ^engine.Scene, camera: ^la.Quaternionf32) {
	log.info("Destroying pumpkin")
	closest_pumpkin: ^engine.Entity
	closest_pumpkin_id: engine.Entity_ID
	value: f32 = -1
	#reverse for &entity, i in engine.sparse_array_slice(&scene.entities) {
		if entity.tag == .Pumpkin {
			pumpkin_forward_vec := la.quaternion_mul_vector3(entity.transform.rotation, [3]f32{0, 0, -1})
			// pumpkin_forward_vec.x = -pumpkin_forward_vec.x // Swizzle the x was a tricky bug to find be careful if changing
			temp_value := la.dot(la.quaternion_mul_vector3(camera^, [3]f32{1, 0, 0}), pumpkin_forward_vec)
			if temp_value > value {
				closest_pumpkin = &entity
				closest_pumpkin_id = scene.entities.index_to_key[uint(i)]
				value = temp_value
			}
		}
	}
	if closest_pumpkin != nil {
		// engine.scene_destroy_entity(scene, closest_pumpkin_id, closest_pumpkin)
		explode_pumpkin(closest_pumpkin)
	}
}

explode_pumpkin :: proc(pumpkin: ^engine.Entity,){
	dir := generate_explosion_direction()
	pumpkin.physics.velocity = {dir.x, 25, dir.y}
	pumpkin.couple.physics.velocity = {dir.z, 25, dir.w}
	pumpkin.has_exploded = true
	pumpkin.couple.has_exploded = true
	pumpkin.script.update = nil
	pumpkin.couple.script.update = nil
}

generate_explosion_direction :: proc() -> (result: [4]f32) {
	amount : f32 = 15
	for &v in result {
		v = amount * (rand.float32() - 0.5)
	}
	return result
}
check_pumpkin_collisions :: proc(scene: ^engine.Scene, top: ^engine.Mesh, bot: ^engine.Mesh){
	for &entity, i in engine.sparse_array_slice(&scene.entities) {
		if !entity.has_exploded {
			continue
		}

		if entity.transform.position.y < -1 {
			if !entity.has_collided {
				create_pumpkin(scene, top^, bot^, {entity.transform.position.x, 5, entity.transform.position.z})
				entity.has_collided = true
			}
		}
		if entity.transform.position.y < -100 {	
			engine.scene_destroy_entity(scene, entity.id, &entity)
			log.info("Destroyed")
			return
		}
		for &pumpkin, j in engine.sparse_array_slice(&scene.entities) {
			if pumpkin.tag == .Pumpkin && !pumpkin.has_exploded {
				if dist_check(entity.transform.position, pumpkin.transform.position) {
					explode_pumpkin(&pumpkin)
					log.info("Chain")
					return //per frame optimisation
				}
			}	
		}
	}
}

dist_check :: proc(a:[3]f32, b: [3]f32) -> bool {
	return  la.vector_length2(b-a) < 10
}

import xr "./../dependencies/openxr_odin/openxr"
HAND_COUNT :: 2
AppInputInfo :: struct {
	instance: xr.Instance,
	session:  xr.Session,
	touch_controller_path: xr.Path,
    hand_paths: [HAND_COUNT]xr.Path,
    squeeze_value_paths: [HAND_COUNT]xr.Path,
    trigger_value_paths: [HAND_COUNT]xr.Path,
    pose_paths: [HAND_COUNT]xr.Path,
    haptic_paths: [HAND_COUNT]xr.Path,
    menu_click_paths: [HAND_COUNT]xr.Path,
    action_set: xr.ActionSet,
    grab_action: xr.Action,
    trigger_action: xr.Action,
    trigger_click_action: xr.Action,
    pose_action: xr.Action,
    vibrate_action: xr.Action,
    menu_action: xr.Action,
	hand_locations: [HAND_COUNT]xr.SpaceLocation,
    trigger_states: [HAND_COUNT]xr.ActionStateFloat,
    trigger_click_states: [HAND_COUNT]xr.ActionStateBoolean,
	stage_space: xr.Space,
    hand_spaces: [HAND_COUNT]xr.Space
}

a := AppInputInfo{}
// Create the action set, actions, interaction profile, and attach the action set to the session
init_input :: proc() {
    result: xr.Result
    a.instance = vr.vr_ctx.instance
	a.session = vr.vr_ctx.session
    // Create Action Set
	action_set_desc := xr.ActionSetCreateInfo{
                sType = .ACTION_SET_CREATE_INFO,
                actionSetName = xr.make_string("gameplay", xr.MAX_ACTION_SET_NAME_SIZE),
                localizedActionSetName = xr.make_string("Gameplay", xr.MAX_LOCALIZED_ACTION_SET_NAME_SIZE),
    }
	result = xr.CreateActionSet(a.instance, &action_set_desc, &a.action_set)
    assert(result ==.SUCCESS)

    // Create sub-action paths
	xr.StringToPath(a.instance, "/user/hand/left", &a.hand_paths[0])
	xr.StringToPath(a.instance, "/user/hand/right", &a.hand_paths[1])
	xr.StringToPath(a.instance, "/user/hand/left/input/squeeze/value",  &a.squeeze_value_paths[0])
	xr.StringToPath(a.instance, "/user/hand/right/input/squeeze/value", &a.squeeze_value_paths[1])
	xr.StringToPath(a.instance, "/user/hand/left/input/trigger/value",  &a.trigger_value_paths[0])
	xr.StringToPath(a.instance, "/user/hand/right/input/trigger/value", &a.trigger_value_paths[1])
	xr.StringToPath(a.instance, "/user/hand/left/input/grip/pose", &a.pose_paths[0])
	xr.StringToPath(a.instance, "/user/hand/right/input/grip/pose", &a.pose_paths[1])
	xr.StringToPath(a.instance, "/user/hand/left/output/haptic", &a.haptic_paths[0])
	xr.StringToPath(a.instance, "/user/hand/right/output/haptic", &a.haptic_paths[1])
	xr.StringToPath(a.instance, "/user/hand/left/input/menu/click", &a.menu_click_paths[0])
	xr.StringToPath(a.instance, "/user/hand/right/input/menu/click", &a.menu_click_paths[1])

    // Create Actions
    grab_desc := xr.ActionCreateInfo{
            sType = .ACTION_CREATE_INFO,
            actionType = .FLOAT_INPUT,
            actionName = xr.make_string("grab_object", xr.MAX_ACTION_NAME_SIZE),
            localizedActionName = xr.make_string("Grab Object", xr.MAX_LOCALIZED_ACTION_NAME_SIZE),
            countSubactionPaths = 2,
            subactionPaths = &a.hand_paths[0],
    }
	result = xr.CreateAction(a.action_set, &grab_desc, &a.grab_action)
    assert(result==.SUCCESS)

        trigger_desc := xr.ActionCreateInfo{
                sType = .ACTION_CREATE_INFO,
                actionType = .FLOAT_INPUT,
                actionName = xr.make_string("trigger", xr.MAX_ACTION_NAME_SIZE),
                localizedActionName = xr.make_string("Trigger", xr.MAX_LOCALIZED_ACTION_NAME_SIZE),
                countSubactionPaths = 2,
                subactionPaths = &a.hand_paths[0],
        }
	result = xr.CreateAction(a.action_set, &trigger_desc, &a.trigger_action)
    assert(result==.SUCCESS)

        click_desc := xr.ActionCreateInfo{
                sType = .ACTION_CREATE_INFO,
                actionType = .BOOLEAN_INPUT,
                actionName = xr.make_string("trigger_click", xr.MAX_ACTION_NAME_SIZE),
                localizedActionName = xr.make_string("Trigger Click", xr.MAX_LOCALIZED_ACTION_NAME_SIZE),
                countSubactionPaths = 2,
                subactionPaths = &a.hand_paths[0],
        }
	result = xr.CreateAction(a.action_set, &click_desc, &a.trigger_click_action)
    assert(result==.SUCCESS)

        pose_desc := xr.ActionCreateInfo{
                sType = .ACTION_CREATE_INFO,
                actionType = .POSE_INPUT,
                actionName = xr.make_string("hand_pose", xr.MAX_ACTION_NAME_SIZE),
                localizedActionName = xr.make_string("Hand Pose", xr.MAX_LOCALIZED_ACTION_NAME_SIZE),
                countSubactionPaths = 2,
                subactionPaths = &a.hand_paths[0],
        }
	result = xr.CreateAction(a.action_set, &pose_desc, &a.pose_action)
    assert(result==.SUCCESS)

        vibrate_desc := xr.ActionCreateInfo{
                sType = .ACTION_CREATE_INFO,
                actionType = .VIBRATION_OUTPUT,
                actionName = xr.make_string("vibrate_hand", xr.MAX_ACTION_NAME_SIZE),
                localizedActionName = xr.make_string("Vibrate Hand", xr.MAX_LOCALIZED_ACTION_NAME_SIZE),
                countSubactionPaths = 2,
                subactionPaths = &a.hand_paths[0],
        }
	result = xr.CreateAction(a.action_set, &vibrate_desc, &a.vibrate_action)
    assert(result==.SUCCESS)

        menu_desc := xr.ActionCreateInfo{
                sType = .ACTION_CREATE_INFO,
                actionType = .BOOLEAN_INPUT,
                actionName = xr.make_string("quit_session", xr.MAX_ACTION_NAME_SIZE),
                localizedActionName = xr.make_string("Menu Button", xr.MAX_LOCALIZED_ACTION_NAME_SIZE),
                countSubactionPaths = 2,
                subactionPaths = &a.hand_paths[0],
        }
	result = xr.CreateAction(a.action_set, &menu_desc, &a.menu_action)
    assert(result==.SUCCESS)

        // Oculus Touch Controller Interaction Profile
        xr.StringToPath(a.instance, "/interaction_profiles/oculus/touch_controller", &a.touch_controller_path)
        bindings := [?]xr.ActionSuggestedBinding{
                {a.grab_action, a.squeeze_value_paths[0]},
                {a.grab_action, a.squeeze_value_paths[1]},
                {a.trigger_action, a.trigger_value_paths[0]},
                {a.trigger_action, a.trigger_value_paths[1]},
                {a.trigger_click_action, a.trigger_value_paths[0]},
                {a.trigger_click_action, a.trigger_value_paths[1]},
                {a.pose_action, a.pose_paths[0]},
                {a.pose_action, a.pose_paths[1]},
                {a.menu_action, a.menu_click_paths[0]},
                {a.vibrate_action, a.haptic_paths[0]},
                {a.vibrate_action, a.haptic_paths[1]},
        }
        suggested_bindings := xr.InteractionProfileSuggestedBinding{
                sType = .INTERACTION_PROFILE_SUGGESTED_BINDING,
                interactionProfile = a.touch_controller_path,
                suggestedBindings = &bindings[0],
                countSuggestedBindings = len(bindings),
        }
        result = xr.SuggestInteractionProfileBindings(a.instance, &suggested_bindings)
    assert(result==.SUCCESS)

        // Hand Spaces
	action_space_desc := xr.ActionSpaceCreateInfo{
                sType = .ACTION_SPACE_CREATE_INFO,
                action = a.pose_action,
                poseInActionSpace = {{0.0, 0.0, 0.0, 1.0}, {0.0, 0.0, 0.0}},
                subactionPath = a.hand_paths[0],
        }
	result = xr.CreateActionSpace(a.session, &action_space_desc, &a.hand_spaces[0])
    assert(result==.SUCCESS)
	action_space_desc.subactionPath = a.hand_paths[1]
	result = xr.CreateActionSpace(a.session, &action_space_desc, &a.hand_spaces[1])
    assert(result==.SUCCESS)

        // Attach Action Set
	session_actions_desc := xr.SessionActionSetsAttachInfo{
                sType = .SESSION_ACTION_SETS_ATTACH_INFO,
                countActionSets = 1,
                actionSets = &a.action_set,
        }
	result = xr.AttachSessionActionSets(a.session, &session_actions_desc)
    assert(result==.SUCCESS)
}

get_input:: proc() -> bool {
	if (!vr.vr_ctx.is_focused) {
		return false
	}
	active_action_set := xr.ActiveActionSet{
        actionSet = a.action_set,
        subactionPath = xr.Path(0),
	}
    action_sync_info := xr.ActionsSyncInfo{
            sType = .ACTIONS_SYNC_INFO,
            next = nil,
            countActiveActionSets = 1,
            activeActionSets = &active_action_set,
    }
    result := xr.SyncActions(a.session, &action_sync_info)
    assert(result == .SUCCESS)
    
 // Get Action States and Spaces (i.e. current state of the controller inputs)
    for i in 0 ..< HAND_COUNT {
            a.hand_locations[i].sType = .SPACE_LOCATION
            a.trigger_states[i].sType = .ACTION_STATE_FLOAT
            a.trigger_click_states[i].sType = .ACTION_STATE_BOOLEAN
    }
    action_get_info := xr.ActionStateGetInfo{    
	    sType = .ACTION_STATE_GET_INFO,
	    action = a.trigger_click_action,
	    subactionPath = a.hand_paths[1],
	}
	result = xr.GetActionStateBoolean(vr.vr_ctx.session, &action_get_info, &a.trigger_click_states[1])
	return bool(a.trigger_click_states[1].currentState && a.trigger_click_states[1].changedSinceLastSync)
}

