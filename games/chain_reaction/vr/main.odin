package main

import "../../../kinetica/core"
import "../engine/vr"
import "core:mem"
import vk "vendor:vulkan"

main :: proc() {
	tracker: ^mem.Tracking_Allocator
	tracker, context.allocator = core.init_tracker()
	context.logger = core.init_logger("log.txt", .Jack, .All)
	core.window_create(600, 800, "VR Example")
	vk_info := core.vk_info_get()
	vr.init(vk_info)
	defer {
		vr.destroy()
		defer core.destroy_tracker(tracker)
	}

	for !core.window_should_close() {
		should_render := vr.event_poll(vk_info)
		if should_render {
			// begin frame

			// begin first view

			// render from given view
			render_data: engine.VR_Render_Data
			engine.renderer_render_scene_vr(&scene, &render_data)
				
			core.vk_command_image_barrier(
				command_buffer  = command_buffers[frame],
				image           = &pixel_image,
				dst_access_mask = {.COLOR_ATTACHMENT_WRITE},
				old_layout      = .UNDEFINED,
				new_layout      = .COLOR_ATTACHMENT_OPTIMAL,
			)

			core.vk_command_image_barrier(
				command_buffers[frame],
				image             = &depth_image,
				dst_access_mask   = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
				old_layout        = .UNDEFINED,
				new_layout        = .DEPTH_ATTACHMENT_OPTIMAL,
				subresource_range = {{.DEPTH}, 0, 1, 0, 1}
			)
			depth_attachment := core.vk_depth_attachment_create(depth_image.view)
	
			core.vk_command_begin_rendering(
				command_buffer = command_buffers[frame],
				render_area = {
					offset = {0, 0},
					extent = extent
				},
				color_attachments = {
					core.vk_color_attachment_create(pixel_image.view)
				},
				depth_attachment = &depth_attachment
			)
	
			core.vk_command_viewport_set(
				command_buffers[frame],
				{{
					x        = 0,
					y        = 0,
					width    = f32(extent.width),
					height   = f32(extent.height),
					minDepth = 0,
					maxDepth = 1,
				}}
			)

			core.vk_command_scissor_set(
				command_buffers[frame],
				{{
					offset = {0, 0},
					extent = extent
				}}
			)
			core.vk_command_graphics_pipeline_bind(command_buffers[frame], pipeline)
	
			cold_data.view_projection = core.camera_3d_get_view_projection(camera)
			cold_data.camera_position = camera.position.xyzz
			cold_data.ambient_color = scene.ambient_color.xyzz
			cold_data.ambient_strength = scene.ambient_strength
			for i in 0..<scene.point_light_count do cold_data.point_lights[i] = scene.point_lights[i]
			cold_data.point_light_count = scene.point_light_count
	
			core.vk_buffer_copy(transfer_pool, &cold_ssbo, &cold_data, &vk_allocator)
			core.vk_descriptor_set_update_storage_buffer(descriptor_sets[frame], 0, &cold_ssbo)

			instance_index, mesh_index: u32
			for mesh, &entity_array in scene.meshes {
				instance_ranges[mesh_index][0] = instance_index
		
				for entity_id in sparse_array_slice(&entity_array) {
					entity := sparse_array_get(&scene.entities, entity_id)
					hot_data.model_matrices[instance_index] = core.transform_get_matrix(&entity.transform)
					instance_index += 1
				}
				instance_ranges[mesh_index][1] = instance_index - instance_ranges[mesh_index][0]
				mesh_index += 1
			}
			core.vk_buffer_copy(transfer_pool, &hot_ssbo, &hot_data, &vk_allocator)
			core.vk_descriptor_set_update_storage_buffer(descriptor_sets[frame], 1, &hot_ssbo)
	
			core.vk_command_descriptor_set_bind(command_buffers[frame], pipeline_layout, .GRAPHICS, descriptor_sets[frame])

			mesh_index = 0
			for mesh, _ in scene.meshes {
				mesh_hot := resource_manager_get_mesh_hot(mesh)
				core.vk_command_vertex_buffers_bind(command_buffers[frame], {mesh_hot.vertex_buffer.handle})
				core.vk_command_index_buffer_bind(command_buffers[frame], mesh_hot.index_buffer.handle)
		
				core.vk_command_draw_indexed(
					command_buffer = command_buffers[frame],
					index_count    = mesh_hot.index_count,
					instance_count = instance_ranges[mesh_index][1],
					first_instance = instance_ranges[mesh_index][0]
				)
				mesh_index += 1
			}

			core.vk_command_end_rendering(command_buffers[frame])

			core.vk_command_image_barrier(
				command_buffer  = command_buffers[frame],
				image           = &pixel_image,
				src_access_mask = {.COLOR_ATTACHMENT_WRITE},
				dst_access_mask = {.SHADER_READ},
				old_layout      = .COLOR_ATTACHMENT_OPTIMAL,
				new_layout      = .SHADER_READ_ONLY_OPTIMAL,
			)

			core.vk_command_image_barrier(
				command_buffer  = command_buffers[frame],
				image           = core.vk_swapchain_get_image(index),
				dst_access_mask = {.COLOR_ATTACHMENT_WRITE},
				old_layout      = .PRESENT_SRC_KHR,
				new_layout      = .COLOR_ATTACHMENT_OPTIMAL,
			)
	
			core.vk_command_begin_rendering(
				command_buffer = command_buffers[frame],
				render_area = {
					offset = {0, 0},
					extent = extent
				},
				color_attachments = {
					core.vk_color_attachment_create(core.vk_swapchain_get_image_view(index))
				}
			)
	
			core.vk_command_viewport_set(
				command_buffers[frame],
				{{
					x        = 0,
					y        = 0,
					width    = f32(extent.width),
					height   = f32(extent.height),
				}}
			)

			core.vk_command_scissor_set(
				command_buffers[frame],
				{{
					offset = {0, 0},
					extent = extent
				}}
			)

			core.vk_command_graphics_pipeline_bind(command_buffers[frame], pixel_pipeline)
			core.vk_descriptor_set_update_uniform_buffer(pixel_descriptor_sets[frame], 0, &pixel_ubo)
			core.vk_descriptor_set_update_image(pixel_descriptor_sets[frame], 1, &pixel_image, pixel_sampler)
			core.vk_command_descriptor_set_bind(command_buffers[frame], pixel_pipeline_layout, .GRAPHICS, pixel_descriptor_sets[frame])
			core.vk_command_vertex_buffers_bind(command_buffers[frame], {quad_vertex_buffer.handle})
			core.vk_command_index_buffer_bind(command_buffers[frame], quad_index_buffer.handle)
			core.vk_command_draw_indexed(command_buffers[frame], u32(len(quad_indices)))
			core.vk_command_end_rendering(command_buffers[frame])
	
			core.vk_command_image_barrier(
				command_buffer  = command_buffers[frame],
				image           = core.vk_swapchain_get_image(index),
				src_access_mask = {.COLOR_ATTACHMENT_WRITE},
				old_layout      = .COLOR_ATTACHMENT_OPTIMAL,
				new_layout      = .PRESENT_SRC_KHR,			
			)

			core.vk_command_buffer_end(command_buffers[frame])

			core.vk_queue_submit(
				command_buffers[frame],
				render_finished[index],
				image_available[frame],
				{.COLOR_ATTACHMENT_OUTPUT},
				block_until[frame]
			)
	
			core.vk_present(render_finished[index], index)		

			// end first

			// begin second view

			// render from given view

			// end second

			// end frame

			vr.render_frame()
		}
	}

}

