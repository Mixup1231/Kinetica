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
	core.transform_rotate(&transform, {0, 1, 0}, -la.PI / 4)
	engine.scene_register_mesh_component(&scene, one, car_mesh, transform)

	_, light := engine.scene_insert_point_light(&scene)
	light.color = {0.3, 0.3, 0.8, 1}
	light.position = {0, 4, 0, 1}

	fs: bool
	dt, pixel_size, max_pixel_size: f32 = 0, 4, 8
	start, end: time.Tick
	axis: [3]f32 = {1, 0, 0}
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

		should_render := vr.event_poll(vk_info)
		if should_render {
			frame_data := vr.begin_frame()
			if !frame_data.frame_state.shouldRender {
				vr.end_frame(&frame_data)
				continue
			}
			
			for i in 0..<frame_data.submit_count {
				view  := &frame_data.views[i]
				view.pose.position.y += 5
				image := vr.acquire_next_swapchain_image(i)
				
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
		
	}
}
