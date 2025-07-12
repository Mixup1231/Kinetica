package main

import "core:fmt"
import "core:log"
import "core:time"
import la "core:math/linalg"

import "../../../kinetica/core"
import "../engine"

import vk "vendor:vulkan"

camera: core.Camera_3D
fovy := la.to_radians(f32(80))
update_camera_projection :: proc(
	extent: vk.Extent2D
) {
	core.camera_3d_set_projection(&camera, fovy, f32(extent.width)/f32(extent.height), 0.1, 100)
}
	
main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)
	
	core.window_create(800, 600, "Oh my Gourd!")
	defer core.window_destroy()

	core.vk_swapchain_set_recreation_callback(update_camera_projection)
	
	core.input_set_mouse_mode(.Locked)

	engine.resource_manager_init()
	defer engine.resource_manager_destory()

	engine.renderer_init()
	defer engine.renderer_destroy()

	scene_mesh := engine.resource_manager_load_mesh("games/chain_reaction/assets/models/GDC_Scene11-07-25.obj", {})
	defer engine.resource_manager_destroy_mesh(scene_mesh)	

	scene := engine.scene_create()
	defer engine.scene_destroy(&scene)

	scene.ambient_strength = 0
	scene.ambient_color = {1, 1, 1}	
	
	one, _ := engine.scene_insert_entity(&scene)
	transform := core.transform_create()
	core.transform_rotate(&transform, {1, 0, 0}, la.PI)
	engine.scene_register_mesh_component(&scene, one, scene_mesh, transform)

	_, light := engine.scene_insert_point_light(&scene)
	light.color = {0.3, 0.3, 0.8, 1}
	light.position = {0, -4, 0, 1}

	camera = core.camera_3d_create(f32(800)/f32(600), fovy = fovy, speed = 4)

	// create pumpkin
	pumpkin_top_mesh := engine.resource_manager_load_mesh("games/chain_reaction/assets/models/pumpkin-top.obj", {})
	defer engine.resource_manager_destroy_mesh(pumpkin_top_mesh)	
	pumpkin_bot_mesh := engine.resource_manager_load_mesh("games/chain_reaction/assets/models/pumpkin-bot.obj", {})
	defer engine.resource_manager_destroy_mesh(pumpkin_bot_mesh)	
	for i in 0..<20 {
		create_pumpkin(&scene, pumpkin_top_mesh, pumpkin_bot_mesh)
	}

	fs: bool
	dt, pixel_size, max_pixel_size: f32 = 0, 0, 8
	start, end: time.Tick
	start_app_time := time.now()
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
		app_time = f32(time.duration_seconds(time.diff(start_app_time, time.now())))
		
		engine.scene_update_entities(&scene, dt)
		engine.scene_update_physics_entities(&scene, dt)

		vecs := core.camera_3d_get_vectors(&camera)
		vecs[.Front] = vecs[.Right].zyx
		vecs[.Front].z *= -1
		
		if core.input_is_key_held(.Key_W) {
			camera.position += vecs[.Front] * dt * camera.speed
		}
		if core.input_is_key_held(.Key_S) {
			camera.position -= vecs[.Front] * dt * camera.speed
		}
		if core.input_is_key_held(.Key_D) {
			camera.position += vecs[.Right] * dt * camera.speed
		}
		if core.input_is_key_held(.Key_A) {
			camera.position -= vecs[.Right] * dt * camera.speed
		}
		if core.input_is_key_held(.Key_Space) {
			camera.position += {0, -1, 0} * dt * camera.speed
		}
		if core.input_is_key_held(.Key_Left_Shift) {
			camera.position += {0, 1, 0} * dt * camera.speed
		}
		if core.input_is_key_pressed(.Key_P) {
			destroy_pumpkin(&scene, &camera)
		}
		if core.input_is_key_pressed(.Key_O) {
			for i in 0..<20 {
				create_pumpkin(&scene, pumpkin_top_mesh, pumpkin_bot_mesh)
			}
		}
		
		core.camera_3d_update(&camera, core.input_get_relative_mouse_pos_f32())

		engine.renderer_render_scene_swapchain(&scene, &camera)

		end = time.tick_now()
	}
}

import "core:math/rand"
import "core:math"
create_pumpkin :: proc(scene: ^engine.Scene, pumpkin_top_mesh: engine.Mesh, pumpkin_bot_mesh: engine.Mesh) {
	range :f32 = 15
	spawn := generate_spawn_pos(range)
	top, e1 := engine.scene_insert_entity(scene)
	e1.tag = .Pumpkin
	transform := core.transform_create()
	core.transform_translate(&transform, {spawn.x, -1.5 -(math.abs(spawn.x) - math.abs(spawn.z))/f32(range), spawn.z})
	core.transform_rotate(&transform, {1, 0, 0}, la.PI)
	core.transform_look_at(&transform, {0, -2, 0})
	engine.scene_register_mesh_component(scene, top, pumpkin_top_mesh, transform)
	engine.scene_register_physics_component(scene, top, {})
	add_pumpkin_animation(scene, top)
	bot, e2 := engine.scene_insert_entity(scene)
	e2.tag = .Pumpkin
	transform = core.transform_create()
	core.transform_translate(&transform, {spawn.x, -1.5 -(math.abs(spawn.x) - math.abs(spawn.z))/f32(range), spawn.z})
	core.transform_rotate(&transform, {1, 0, 0}, la.PI)
	core.transform_look_at(&transform, {0, -2, 0})
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
app_time : f32
move_pumpkin_head :: proc(ts: f32, pumpkin : ^engine.Entity) {
	pumpkin_forward_vec := -pumpkin.transform.position
	core.transform_rotate(&pumpkin.transform, {0, 0, 1}, pumpkin_move_function(ts, app_time, {2, 6}, {1, 2}))
}

pumpkin_move_function :: proc(ts: f32, app_time: f32, periods: [2]f32, amplitudes: [2]f32) -> f32 {
	return ts * (amplitudes[0] * f32(la.sin(periods[0]  * app_time) + amplitudes[1]) * f32(la.sin(periods[1] * app_time)))
}

add_pumpkin_animation :: proc(scene: ^engine.Scene, pumpkin_head: engine.Entity_ID) {
	script := engine.Script {
		update = move_pumpkin_head,
		fixed_update = move_pumpkin_head,
	}
	engine.scene_register_script_component(scene, pumpkin_head, script)
}

destroy_pumpkin :: proc(scene: ^engine.Scene, camera: ^core.Camera_3D) {
	log.info("Destroying pumpkin")
	closest_pumpkin: ^engine.Entity
	closest_pumpkin_id: engine.Entity_ID
	value: f32 = -1
	#reverse for &entity, i in engine.sparse_array_slice(&scene.entities) {
		if entity.tag == .Pumpkin {
			pumpkin_forward_vec := la.quaternion_mul_vector3(entity.transform.rotation, [3]f32{0, 0, -1})
			pumpkin_forward_vec.x = -pumpkin_forward_vec.x // Swizzle the x was a tricky bug to find be careful if changing
			temp_value := la.dot(la.quaternion_mul_vector3(camera.rotation, [3]f32{1, 0, 0}), pumpkin_forward_vec)
			if temp_value > value {
				closest_pumpkin = &entity
				closest_pumpkin_id = scene.entities.index_to_key[uint(i)]
				value = temp_value
			}
		}
	}
	if closest_pumpkin != nil {
		// engine.scene_destroy_entity(scene, closest_pumpkin_id, closest_pumpkin)
		dir := generate_explosion_direction()
		closest_pumpkin.physics.velocity = {dir.x, -25, dir.y}
		closest_pumpkin.couple.physics.velocity = {dir.z, -25, dir.w}
	}
}

generate_explosion_direction :: proc() -> (result: [4]f32) {
	amount : f32 = 15
	for &v in result {
		v = amount * (rand.float32() - 0.5)
	}
	return result
}
