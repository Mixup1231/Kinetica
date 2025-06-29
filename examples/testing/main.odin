package main

import "core:os"
import "core:log"

import "../../kinetica/core"

g_width: i32 = 1920
g_height: i32 = 1080

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	core.window_create(g_width, g_height, "test")
	defer core.window_destroy()

	format              := core.vulkan_get_swapchain_color_format()
	rendering_info      := core.vulkan_rendering_info_create(color_attachment_formats = {format})	
	vertex_state        := core.vulkan_vertex_input_state_create()
	assembly_state      := core.vulkan_input_assembly_state_create()
	viewport_state      := core.vulkan_viewport_state_create()
	rasterization_state := core.vulkan_rasterizer_state_create()
	multisample_state   := core.vulkan_multisample_state_create()
	color_attachment    := core.vulkan_color_attachment_state_create()
	color_state         := core.vulkan_color_blend_state_create(attachments = {color_attachment})
	dynamic_state       := core.vulkan_dynamic_state_create({.VIEWPORT, .SCISSOR})
	
	vert := core.vulkan_shader_module_create("./shaders/test.vert.spv")
	frag := core.vulkan_shader_module_create("./shaders/test.frag.spv")
	
	pipeline, pipeline_layout := core.vulkan_graphics_pipeline_create(
		&rendering_info,
		&vertex_state,
		&assembly_state,
		&viewport_state,
		&rasterization_state,
		&multisample_state,
		&color_state,
		&dynamic_state,
		{
			core.vulkan_shader_stage_state_create({.VERTEX}, vert),
			core.vulkan_shader_stage_state_create({.FRAGMENT}, frag)
		},
	)
		
	Frames_In_Flight := core.vulkan_swapchain_get_image_count()
	command_pool    := core.vulkan_command_pool_create(.Graphics)
	command_buffers := core.vulkan_command_buffer_create(command_pool, .PRIMARY, Frames_In_Flight)	
	signal_rendered := core.vulkan_semaphore_create(Frames_In_Flight)
	wait_available  := core.vulkan_semaphore_create(Frames_In_Flight) 
	in_flight       := core.vulkan_fence_create(true, Frames_In_Flight)	

	defer {
		core.vulkan_command_pool_destroy(command_pool)
		core.vulkan_semaphore_destroy(signal_rendered)
		core.vulkan_semaphore_destroy(wait_available)
		core.vulkan_fence_destroy(in_flight)
		core.vulkan_shader_module_destroy(vert)
		core.vulkan_shader_module_destroy(frag)
		core.vulkan_graphics_pipeline_destroy(pipeline, pipeline_layout)
	}

	image_index: u32
	frame: u32
	for !core.window_should_close() {
		core.window_poll()

		if core.input_is_key_pressed(.Key_Escape) {
			core.window_set_should_close(true)
		}

		frame = (frame + 1) % Frames_In_Flight

		extent := core.vulkan_swapchain_get_extent()
		image_index = core.vulkan_swapchain_get_next_image_index(wait_available[frame], in_flight[frame])

		core.vulkan_command_buffer_reset(command_buffers[frame])
		core.vulkan_command_buffer_begin(command_buffers[frame])	

		core.vulkan_command_image_barrier(
			command_buffer  = command_buffers[frame],
			image           = core.vulkan_swapchain_get_image(image_index),
			dst_access_mask = {.COLOR_ATTACHMENT_WRITE},
			old_layout      = .UNDEFINED,
			new_layout      = .COLOR_ATTACHMENT_OPTIMAL,
			src_stage_mask  = {.TOP_OF_PIPE},
			dst_stage_mask  = {.COLOR_ATTACHMENT_OUTPUT},
		)
	
		core.vulkan_command_begin_rendering(
			command_buffer = command_buffers[frame],
			render_area = {
				offset = {0, 0},
				extent = extent
			},
			color_attachments = {
				core.vulkan_color_attachment_create(core.vulkan_swapchain_get_image_view(image_index))
			}
		)
		
		core.vulkan_command_viewport_set(
			command_buffers[frame],
			{{
				x = 0,
				y = 0,
				width = f32(extent.width),
				height = f32(extent.height)
			}}
		)

		core.vulkan_command_scissor_set(
			command_buffers[frame],
			{{
				offset = {0, 0},
				extent = extent
			}}
		)
		
		core.vulkan_command_graphics_pipeline_bind(command_buffers[frame], pipeline)

		core.vulkan_command_draw(command_buffers[frame], 3)

		core.vulkan_command_end_rendering(command_buffers[frame])

		core.vulkan_command_image_barrier(
			command_buffer  = command_buffers[frame],
			image           = core.vulkan_swapchain_get_image(image_index),
			src_stage_mask  = {.COLOR_ATTACHMENT_OUTPUT},
			dst_stage_mask  = {.BOTTOM_OF_PIPE},
			src_access_mask = {.COLOR_ATTACHMENT_WRITE},
			old_layout      = .COLOR_ATTACHMENT_OPTIMAL,
			new_layout      = .PRESENT_SRC_KHR,			
		)
		
		core.vulkan_command_buffer_end(command_buffers[frame])

		core.vulkan_submit_to_queue(
			.Graphics,
			command_buffers[frame],
			signal_rendered[frame],
			wait_available[frame],
			{.COLOR_ATTACHMENT_OUTPUT},
			in_flight[frame]
		)

		core.vulkan_present(signal_rendered[frame], image_index)
	}
}
