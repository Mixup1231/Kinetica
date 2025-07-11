package main

import "core:fmt"
import "core:log"
import "core:time"
import la "core:math/linalg"
import oxr "../dependencies/openxr_odin/openxr"

import "../../../kinetica/core"
import "../engine"
import "../engine/vr"

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
	
	core.vk_swapchain_set_recreation_callback(update_camera_projection)
	
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
	
	one, _ := engine.scene_insert_entity(&scene)
	transform := core.transform_create()
	core.transform_rotate(&transform, {1, 0, 0}, la.PI)
	engine.scene_register_mesh_component(&scene, one, car_mesh, transform)

	_, light := engine.scene_insert_point_light(&scene)
	light.color = {0.3, 0.3, 0.8, 1}
	light.position = {0, -4, 0, 1}

	camera = core.camera_3d_create(f32(800)/f32(600), fovy = fovy, speed = 4)

	fs: bool
	dt, pixel_size, max_pixel_size: f32 = 0, 4, 8
	start, end: time.Tick
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
		
		core.camera_3d_update(&camera, core.input_get_relative_mouse_pos_f32())

		// engine.renderer_render_scene_swapchain(&scene, &camera)

		should_render := vr.event_poll(vk_info)
		if should_render {
			frame_state, render_info, views := vr.begin_frame()
			defer delete(views)
			
			if !frame_state.shouldRender {
				vr.end_frame(&frame_state, &render_info, false)
				continue
			} 

			for &view, i in views {
				image_view := vr.acquire_next_swapchain_view(&render_info, &view, u32(i))
				
				pose := render_info.layer_projection_views[i].pose
				
				render_data: engine.VR_Render_Data = {
					image_index = u32(i),
					image_view  = image_view,
					camera = {
						position = {pose.position.x, pose.position.y, pose.position.z},
						projection = vr.get_view_projection(&render_info.layer_projection_views[i].fov, 0.05, 100, &pose)
					}
				}
				engine.renderer_render_scene_vr(&scene, &render_data)
				vr.release_swapchain_image_view(u32(i))
			}
			
			vr.end_frame(&frame_state, &render_info, true)
			clear(&render_info.layers)
		}

		end = time.tick_now()
	}
}
