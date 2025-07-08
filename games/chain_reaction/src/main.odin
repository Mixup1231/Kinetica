package main

import "core:fmt"
import "core:log"
import "core:time"
import la "core:math/linalg"

import "../../../kinetica/core"

import "../engine"

camera: core.Camera_3D

car_update :: proc(dt: f32, car: ^engine.Entity) {
	core.transform_rotate(&car.transform, {0, 1, 0}, dt)
}

car_two_update :: proc(dt: f32, car: ^engine.Entity) {
	vecs := core.camera_3d_get_vectors(&camera)
	vecs[.Front] = vecs[.Right].zyx
	vecs[.Front].z *= -1
	
	transform := &car.transform
	transform.position = la.lerp(transform.position, camera.position + vecs[.Front], dt)
	core.transform_rotate(transform, {1, 1, 1}, dt)
}
	
main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)
	
	core.window_create(800, 600, "Oh my Gourd!")
	defer core.window_destroy()
	
	core.input_set_mouse_mode(.Locked)

	engine.resource_manager_init()
	defer engine.resource_manager_destory()

	engine.renderer_init()
	defer engine.renderer_destroy()

	car_mesh := engine.resource_manager_load_mesh("games/chain_reaction/assets/models/test2.obj", {})
	defer engine.resource_manager_destroy_mesh(car_mesh)

	scene := engine.scene_create()
	defer engine.scene_destroy(&scene)

	scene.ambient_strength = 0.01
	scene.ambient_color = {1, 1, 1}	
	
	one, _ := engine.scene_insert_entity(&scene)
	transform := core.transform_create()
	engine.scene_register_mesh_component(&scene, one, car_mesh, transform)
	engine.scene_register_script_component(&scene, one, {update = car_update})

	two, _ := engine.scene_insert_entity(&scene)
	core.transform_translate(&transform, {2, 0, 0})
	transform.scale = {0.1, 0.1, 0.1}
	engine.scene_register_mesh_component(&scene, two, car_mesh, transform)
	engine.scene_register_script_component(&scene, two, {update = car_two_update})

	_, light := engine.scene_insert_point_light(&scene)
	light.color = {1, 1, 1, 1}
	light.position = {1, -3, 0, 1}

	_, light_two := engine.scene_insert_point_light(&scene)
	light_two.color = {0.3, 0.3, 1, 1}
	light_two.position = {2, 3, 0, 1}

	camera = core.camera_3d_create(f32(800)/f32(600), speed = 2)

	dt: f32
	start, end: time.Tick
	for !core.window_should_close() {
		core.window_poll()
		
		if core.input_is_key_pressed(.Key_Escape) do core.window_set_should_close(true)

		dt = f32(time.duration_seconds(time.tick_diff(start, end)))
		start = time.tick_now()
		
		engine.scene_update_entities(&scene, dt)

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
		if core.input_is_key_pressed(.Key_C) {
			core.camera_3d_set_fovy(&camera, la.to_radians(f32(20)))
		}
		if core.input_is_key_released(.Key_C) {
			core.camera_3d_set_fovy(&camera, la.to_radians(f32(60)))
		}
		
		core.camera_3d_update(&camera, core.input_get_relative_mouse_pos_f32())

		engine.renderer_render_scene_swapchain(&scene, &camera)

		end = time.tick_now()
	}
}
