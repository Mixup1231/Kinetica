package main

import "core:os"
import "core:log"

import "../../kinetica/core"

import vk "vendor:vulkan"

Vertex :: struct {
	position: [2]f32,
	color:    [3]f32,
	uv:       [2]f32,
}

g_width: i32 = 1920
g_height: i32 = 1080

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	core.window_create(g_width, g_height, "test")
	defer core.window_destroy()

	format              := core.vk_get_swapchain_color_format()
	rendering_info      := core.vk_rendering_info_create(color_attachment_formats = {format})	
	binding, attributes := core.vk_vertex_description_create(Vertex)
	defer delete(attributes)
	vertex_state        := core.vk_vertex_input_state_create({binding}, attributes)
	assembly_state      := core.vk_input_assembly_state_create()
	viewport_state      := core.vk_viewport_state_create()
	rasterization_state := core.vk_rasterizer_state_create()
	multisample_state   := core.vk_multisample_state_create()
	color_attachment    := core.vk_color_attachment_state_create()
	color_state         := core.vk_color_blend_state_create(attachments = {color_attachment})
	dynamic_state       := core.vk_dynamic_state_create({.VIEWPORT, .SCISSOR})
	
	vert := core.vk_shader_module_create("./shaders/test.vert.spv")
	frag := core.vk_shader_module_create("./shaders/test.frag.spv")
	
	pipeline, pipeline_layout := core.vk_graphics_pipeline_create(
		&rendering_info,
		&vertex_state,
		&assembly_state,
		&viewport_state,
		&rasterization_state,
		&multisample_state,
		&color_state,
		&dynamic_state,
		{
			core.vk_shader_stage_state_create({.VERTEX}, vert),
			core.vk_shader_stage_state_create({.FRAGMENT}, frag)
		},
	)
		
	Frames_In_Flight := core.vk_swapchain_get_image_count()
	command_pool    := core.vk_command_pool_create(.Graphics)
	transfer_pool   := core.vk_command_pool_create(.Transfer)
	command_buffers := core.vk_command_buffer_create(command_pool, .PRIMARY, Frames_In_Flight)	
	signal_rendered := core.vk_semaphore_create(Frames_In_Flight)
	wait_available  := core.vk_semaphore_create(Frames_In_Flight) 
	in_flight       := core.vk_fence_create(true, Frames_In_Flight)	

	defer {
		core.vk_command_buffer_destroy(command_pool, command_buffers)
		core.vk_command_pool_destroy(command_pool)
		core.vk_command_pool_destroy(transfer_pool)
		core.vk_semaphore_destroy(signal_rendered)
		core.vk_semaphore_destroy(wait_available)
		core.vk_fence_destroy(in_flight)
		core.vk_shader_module_destroy(vert)
		core.vk_shader_module_destroy(frag)
		core.vk_graphics_pipeline_destroy(pipeline, pipeline_layout)
	}

	quad: [4]Vertex = {
		{
			position = {-0.5, -0.5},
			color    = {1, 0, 0}
		},
		{
			position = {0.5, -0.5},
			color    = {0, 1, 0}
		},
		{
			position = {0.5, 0.5},
			color    = {0, 0, 1}
		},
		{
			position = {-0.5, 0.5},
			color    = {1, 1, 1}
		},
	}

	indices: [6]u32 = {
		0, 1, 2,
		2, 3, 0
	}
	
	vk_allocator := core.vk_allocator_get_default()

	vertex_buffer := core.vk_vertex_buffer_create(size_of(quad), &vk_allocator)
	index_buffer := core.vk_index_buffer_create(size_of(indices), &vk_allocator)

	core.vk_buffer_copy_staged(transfer_pool, &vertex_buffer, raw_data(quad[:]), &vk_allocator)
	core.vk_buffer_copy_staged(transfer_pool, &index_buffer, raw_data(indices[:]), &vk_allocator)
	
	defer {
		core.vk_buffer_destroy(&vertex_buffer)
		core.vk_buffer_destroy(&index_buffer)
	}

	image_index: u32
	frame: u32
	for !core.window_should_close() {
		core.window_poll()

		if core.input_is_key_pressed(.Key_Escape) {
			core.window_set_should_close(true)
		}

		frame = (frame + 1) % Frames_In_Flight

		extent := core.vk_swapchain_get_extent()
		image_index = core.vk_swapchain_get_next_image_index(wait_available[frame], in_flight[frame])

		core.vk_command_buffer_reset(command_buffers[frame])
		core.vk_command_buffer_begin(command_buffers[frame])	

		core.vk_command_image_barrier(
			command_buffer  = command_buffers[frame],
			image           = core.vk_swapchain_get_image(image_index),
			dst_access_mask = {.COLOR_ATTACHMENT_WRITE},
			old_layout      = .UNDEFINED,
			new_layout      = .COLOR_ATTACHMENT_OPTIMAL,
			src_stage_mask  = {.TOP_OF_PIPE},
			dst_stage_mask  = {.COLOR_ATTACHMENT_OUTPUT},
		)
	
		core.vk_command_begin_rendering(
			command_buffer = command_buffers[frame],
			render_area = {
				offset = {0, 0},
				extent = extent
			},
			color_attachments = {
				core.vk_color_attachment_create(core.vk_swapchain_get_image_view(image_index))
			}
		)
		
		core.vk_command_viewport_set(
			command_buffers[frame],
			{{
				x = 0,
				y = 0,
				width = f32(extent.width),
				height = f32(extent.height)
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

		core.vk_command_vertex_buffers_bind(command_buffers[frame], {vertex_buffer.handle})
		core.vk_command_index_buffer_bind(command_buffers[frame], index_buffer.handle)

		vk.CmdDrawIndexed(command_buffers[frame], u32(len(indices)), 1, 0, 0, 0)

		core.vk_command_end_rendering(command_buffers[frame])

		core.vk_command_image_barrier(
			command_buffer  = command_buffers[frame],
			image           = core.vk_swapchain_get_image(image_index),
			src_stage_mask  = {.COLOR_ATTACHMENT_OUTPUT},
			dst_stage_mask  = {.BOTTOM_OF_PIPE},
			src_access_mask = {.COLOR_ATTACHMENT_WRITE},
			old_layout      = .COLOR_ATTACHMENT_OPTIMAL,
			new_layout      = .PRESENT_SRC_KHR,			
		)
		
		core.vk_command_buffer_end(command_buffers[frame])

		core.vk_submit_to_queue(
			.Graphics,
			command_buffers[frame],
			signal_rendered[frame],
			wait_available[frame],
			{.COLOR_ATTACHMENT_OUTPUT},
			in_flight[frame]
		)

		core.vk_present(signal_rendered[frame], image_index)
	}
}
