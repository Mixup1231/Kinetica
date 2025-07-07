package main

import "core:fmt"
import "core:log"
import "core:time"
import la "core:math/linalg"

import "../../../kinetica/core"

import "../engine"

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

	mesh := engine.resource_manager_load_mesh("games/chain_reaction/assets/models/test2.obj", {})
	defer engine.resource_manager_destroy_mesh(mesh)

	scene: engine.Scene
	scene.mesh = mesh

	camera := core.camera_3d_create(f32(800)/f32(600), speed = 2)

	dt: f32
	start, end: time.Tick
	for !core.window_should_close() {
		core.window_poll()
		
		if core.input_is_key_pressed(.Key_Escape) do core.window_set_should_close(true)

		dt = f32(time.duration_seconds(time.tick_diff(start, end)))
		start = time.tick_now()

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
