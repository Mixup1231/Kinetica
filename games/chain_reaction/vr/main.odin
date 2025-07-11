package main

import "../../../kinetica/core"
import "../engine/vr"
import "../engine"
import "core:mem"
import vk "vendor:vulkan"
import la "core:math/linalg"
import oxr "../dependencies/openxr_odin/openxr"
import "core:time"

main :: proc() {
	tracker: ^mem.Tracking_Allocator
	tracker, context.allocator = core.init_tracker()
	context.logger = core.init_logger("log.txt", .Jack, .All)
	core.window_create(800, 600, "VR Example")
	vk_info := core.vk_info_get()
	vr.init(vk_info)
	defer {
		vr.destroy()
		defer core.destroy_tracker(tracker)
	}

	engine.resource_manager_init()
	engine.renderer_init()
	scene := engine.scene_create()
	defer {
		engine.resource_manager_destory()
		engine.renderer_destroy()
		engine.scene_destroy(&scene)
	}

	camera := core.camera_3d_create(f32(800)/f32(600))
	camera.position = {-1, 0, 1}

	car_mesh := engine.resource_manager_load_mesh("games/chain_reaction/assets/models/car.obj", {})
	defer engine.resource_manager_destroy_mesh(car_mesh)

	car, _ := engine.scene_insert_entity(&scene)
	transform := core.transform_create()
	engine.scene_register_mesh_component(&scene, car, car_mesh, transform)

	_, light := engine.scene_insert_point_light(&scene)
	light.color = {1, 1, 1, 1}
	light.position = {0, -3, 0, 0}

	is_valid: bool
	images_info: vr.Swapchain_Images_Info

	for !is_valid {
		vr.event_poll(vk_info)
		images_info, is_valid = vr.get_swapchain_images_info()
		time.sleep(1 * time.Millisecond)
	}
	
	engine.renderer_init_vr({
		image_count = images_info.count,
		extent = images_info.extent,
		format = vk.Format(images_info.format),
	})

	render_data: engine.VR_Render_Data
	for !core.window_should_close() {
		should_render := vr.event_poll(vk_info)
		if should_render {
			// {
			// 	// begin frame
			// 	frame_state, render_info, views := vr.begin_frame()
			// 	defer delete(views)

			// 	for view, i in views {
			// 		// render data
			// 		position := render_info.layer_projection_views[i].pose.position
			// 		projection := la.matrix4_perspective_f32(render_info.layer_projection_views[i].fov)
			// 		render_data = {
			// 			image_view  = view,
			// 			image_index = u32(i),
			// 			camera      = {
			// 				position = {position.x, position.y, position.z},
			// 				projection = render_info
			// 			},
			// 		}
					
			// 		// render
			// 		engine.renderer_render_scene_vr(&scene, )

			// 		vr.release_render_view(u32(i))
			// 	}

			// 	// end frame
			// 	vr.end_frame(&frame_state, &render_info)
			// }
			
			engine.renderer_render_scene_swapchain(&scene, &camera)
		}
	}
}

