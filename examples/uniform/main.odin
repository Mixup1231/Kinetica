package main

import "core:log"
import "core:time"
import "core:math/linalg/glsl"

import "../../kinetica/core"

import vk "vendor:vulkan"

Vertex :: struct {
	position: [2]f32,
	color:    [3]f32,
}

Ubo :: struct {
	model: glsl.mat4,
	view:  glsl.mat4,
	proj:  glsl.mat4,
}

Frames_In_Flight : u32 : 3

Application :: struct {
	vk_allocator:      core.VK_Allocator,
	graphics_pool:     vk.CommandPool,
	transfer_pool:     vk.CommandPool,
	command_buffers:   []vk.CommandBuffer,
	image_available:   []vk.Semaphore,
	render_finished:   []vk.Semaphore,
	block_until:       []vk.Fence,
	vertex_buffer:     core.VK_Buffer,
	index_buffer:      core.VK_Buffer,
	descriptor_pool:   vk.DescriptorPool,
	descriptor_layout: vk.DescriptorSetLayout,
	descriptor_sets:   []vk.DescriptorSet,
	uniform_buffer:    core.VK_Buffer,
	pipeline:          vk.Pipeline,
	pipeline_layout:   vk.PipelineLayout,
	quad_vertices:     [4]Vertex,
	quad_indices:      [6]u16,
	ubo:               Ubo,
}
application: Application

application_create :: proc() {	
	using application
	
	core.window_create(800, 600, "Quad example")
	
	graphics_pool   = core.vk_command_pool_create(.Graphics)
	command_buffers = core.vk_command_buffer_create(graphics_pool, .PRIMARY, Frames_In_Flight)
	image_available = core.vk_semaphore_create(Frames_In_Flight)
	block_until     = core.vk_fence_create(true, Frames_In_Flight)
	
	swapchain_image_count := core.vk_swapchain_get_image_count()
	render_finished = core.vk_semaphore_create(swapchain_image_count)

	quad_vertices = {
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
			color    = {1, 0, 1}
		}
	}

	quad_indices = {
		0, 1, 2,
		2, 3, 0
	}

	vk_allocator   = core.vk_allocator_get_default()
	vertex_buffer  = core.vk_vertex_buffer_create(size_of(quad_vertices), &vk_allocator)
	index_buffer   = core.vk_index_buffer_create(size_of(quad_indices), &vk_allocator)
	uniform_buffer = core.vk_uniform_buffer_create(size_of(ubo), &vk_allocator) 
	
	transfer_pool = core.vk_command_pool_create(.Transfer)
	core.vk_buffer_copy(transfer_pool, &vertex_buffer, raw_data(quad_vertices[:]), &vk_allocator)
	core.vk_buffer_copy(transfer_pool, &index_buffer, raw_data(quad_indices[:]), &vk_allocator)

	swapchain_format := core.vk_swapchain_get_color_format()
	rendering_info   := core.vk_rendering_info_create({swapchain_format}) 

	binding_description, attribute_descriptions := core.vk_vertex_description_create(Vertex)
	defer delete(attribute_descriptions)
	
	vertex_input_state := core.vk_vertex_input_state_create({binding_description}, attribute_descriptions)

	vertex_module := core.vk_shader_module_create("shaders/uniform.vert.spv")
	defer core.vk_shader_module_destroy(vertex_module)
	
	fragment_module := core.vk_shader_module_create("shaders/uniform.frag.spv")
	defer core.vk_shader_module_destroy(fragment_module)
	
	color_blend_attachment_state := core.vk_color_blend_attachment_state_create()
	color_blend_state := core.vk_color_blend_state_create({color_blend_attachment_state})

	descriptor_pool = core.vk_descriptor_pool_create({.UNIFORM_BUFFER}, {Frames_In_Flight}, Frames_In_Flight)
	
	descriptor_layout = core.vk_descriptor_set_layout_create(
		{{
			binding         = 0,
			descriptorType  = .UNIFORM_BUFFER,
			descriptorCount = 1,
			stageFlags      = {.VERTEX},
		}},
	)

	descriptor_layouts: [Frames_In_Flight]vk.DescriptorSetLayout
	for i in 0..<Frames_In_Flight do descriptor_layouts[i] = descriptor_layout
	descriptor_sets = core.vk_descriptor_set_create(descriptor_pool, descriptor_layouts[:])

	input_assembly_state := core.vk_input_assembly_state_create()
	viewport_state       := core.vk_viewport_state_create()
	rasterizer_state     := core.vk_rasterizer_state_create()
	multisample_state    := core.vk_multisample_state_create()
	dynamic_state        := core.vk_dynamic_state_create()	
	
	pipeline, pipeline_layout = core.vk_graphics_pipeline_create(
		&rendering_info,
		&vertex_input_state,
		&input_assembly_state,
		&viewport_state,
		&rasterizer_state,
		&multisample_state,
		&color_blend_state,
		&dynamic_state,
		{
			core.vk_shader_stage_state_create({.VERTEX}, vertex_module, "main"),
			core.vk_shader_stage_state_create({.FRAGMENT}, fragment_module, "main"),
		},
		{descriptor_layout}
	)
}

application_run :: proc() {	
	using application

	dt: f64
	rotation: f32
	start, end: time.Tick
	frame, index: u32
	for !core.window_should_close() {
		core.window_poll()		

		extent := core.vk_swapchain_get_extent()
		
		dt = time.duration_seconds(time.tick_diff(start, end))
		start = time.tick_now()

		rotation += f32(dt) * (glsl.PI / 4) 
		if rotation >= glsl.PI * 2 do rotation = 0
		
		ubo.model = glsl.mat4Rotate({0, 0, 1}, rotation)
		ubo.view = glsl.mat4LookAt({2, 2, -2}, {0, 0, 0}, {0, 1, 0})
		ubo.proj = glsl.mat4Perspective(glsl.radians_f32(45), f32(extent.width) / f32(extent.height), 0.1, 10)
		ubo.proj[1][1] *= -1
				
		core.vk_buffer_copy(&uniform_buffer, &ubo)
	
		frame = (frame + 1) % Frames_In_Flight
		index = core.vk_swapchain_get_next_image_index(image_available[frame], block_until[frame])		
	
		core.vk_command_buffer_reset(command_buffers[frame])
		core.vk_command_buffer_begin(command_buffers[frame])
				
		core.vk_command_image_barrier(
			command_buffer  = command_buffers[frame],
			image           = core.vk_swapchain_get_image(index),
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
				core.vk_color_attachment_create(core.vk_swapchain_get_image_view(index))
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

		core.vk_command_descriptor_set_bind(command_buffers[frame], pipeline_layout, .GRAPHICS, descriptor_sets[frame])
		
		core.vk_descriptor_set_update_uniform_buffer(descriptor_sets[frame], 0, &uniform_buffer)
		
		core.vk_command_vertex_buffers_bind(command_buffers[frame], {vertex_buffer.handle})
		
		core.vk_command_index_buffer_bind(command_buffers[frame], index_buffer.handle, .UINT16)
		
		core.vk_command_draw_indexed(command_buffers[frame], 6)
		
		core.vk_command_end_rendering(command_buffers[frame])

		core.vk_command_image_barrier(
			command_buffer  = command_buffers[frame],
			image           = core.vk_swapchain_get_image(index),
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
			render_finished[index],
			image_available[frame],
			{.COLOR_ATTACHMENT_OUTPUT},
			block_until[frame]
		)

		core.vk_present(render_finished[index], index)		
		
		end = time.tick_now()
	}	
	
	core.vk_command_buffer_destroy(graphics_pool, command_buffers)
	core.vk_command_pool_destroy(graphics_pool)
	core.vk_command_pool_destroy(transfer_pool)
	core.vk_semaphore_destroy(image_available)
	core.vk_semaphore_destroy(render_finished)
	core.vk_fence_destroy(block_until)
	core.vk_buffer_destroy(&vertex_buffer)
	core.vk_buffer_destroy(&index_buffer)
	core.vk_buffer_destroy(&uniform_buffer)
	core.vk_descriptor_set_layout_destroy(descriptor_layout)
	core.vk_descriptor_set_destroy(descriptor_pool, descriptor_sets)
	core.vk_descriptor_pool_destroy(descriptor_pool)
	core.vk_graphics_pipeline_destroy(pipeline, pipeline_layout)
	core.window_destroy()
}


main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)
	
	application_create()
	application_run()
}

