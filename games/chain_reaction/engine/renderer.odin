package engine

import "core:log"

import "../../../kinetica/core"

import vk "vendor:vulkan"

// NOTE(Mitchell): Remember to pad correctly!
Shader_Cold_Data :: struct #align(16) {
	view_projection:   matrix[4, 4]f32,
	point_lights:      [Max_Point_Lights]Point_Light,
	camera_position:   [4]f32,
	ambient_color:     [4]f32,
	ambient_strength:  f32,
	point_light_count: u32,
}

// NOTE(Mitchell): Remember to pad correctly!
Shader_Hot_Data :: struct #align(16) {
	model_matrices:    [Max_Models]matrix[4, 4]f32,
	texture_types:     Texture_Types,
}

Shader_Pixel_Data :: struct {
	resolution: [2]f32,
	pixel_size: f32,
}

Renderer :: struct {
	frame:           u32,
	graphics_pool:   core.VK_Command_Pool,
	transfer_pool:   core.VK_Command_Pool,
	command_buffers: []core.VK_Command_Buffer,
	image_available: []vk.Semaphore,
	render_finished: []vk.Semaphore,
	block_until:     []vk.Fence,
	vk_allocator:    core.VK_Allocator,
	
	descriptor_pool:   vk.DescriptorPool,
	descriptor_layout: vk.DescriptorSetLayout,
	descriptor_sets:   []vk.DescriptorSet,
	samplers:          [Texture_Type]vk.Sampler,
	cold_data:         Shader_Cold_Data,
	cold_ssbo:         core.VK_Buffer,
	hot_data:          Shader_Hot_Data,
	hot_ssbo:          core.VK_Buffer,
	depth_format:      vk.Format,
	depth_image:       core.VK_Image,
	instance_ranges:   [Max_Meshes][2]u32,
	pipeline:          vk.Pipeline,
	pipeline_layout:   vk.PipelineLayout,
	
	quad_vertices:           [4]Vertex,
	quad_indices:            [6]u32,
	quad_vertex_buffer:      core.VK_Buffer,
	quad_index_buffer:       core.VK_Buffer,
	pixel_sampler:           vk.Sampler,
	pixel_image:             core.VK_Image,
	pixel_data:              Shader_Pixel_Data,
	pixel_ubo:               core.VK_Buffer,
	pixel_descriptor_pool:   vk.DescriptorPool,
	pixel_descriptor_layout: vk.DescriptorSetLayout,
	pixel_descriptor_sets:   []vk.DescriptorSet,
	pixel_pipeline_layout:   vk.PipelineLayout,
	pixel_pipeline:          vk.Pipeline,
	
	initialised: bool,
}

@(private="file")
renderer: Renderer

renderer_init :: proc() {
	using renderer 
	ensure(!initialised)
	
	vk_allocator  = core.vk_allocator_get_default()
	transfer_pool = core.vk_command_pool_create(.Transfer)
	
	graphics_pool   = core.vk_command_pool_create(.Graphics)
	command_buffers = core.vk_command_buffer_create(graphics_pool, .PRIMARY, Frames_In_Flight)
	
	image_available = core.vk_semaphore_create(Frames_In_Flight)
	block_until     = core.vk_fence_create(true, Frames_In_Flight)
	
	swapchain_image_count := core.vk_swapchain_get_image_count()
	render_finished = core.vk_semaphore_create(swapchain_image_count)
	
	depth_format = .D32_SFLOAT

	cold_ssbo = core.vk_storage_buffer_create(size_of(Shader_Cold_Data), &vk_allocator)
	hot_ssbo = core.vk_storage_buffer_create(size_of(Shader_Hot_Data), &vk_allocator)
	
	swapchain_format := core.vk_swapchain_get_image_format()
	rendering_info   := core.vk_rendering_info_create({swapchain_format}, depth_format)

	binding_description, attribute_descriptions := core.vk_vertex_description_create(Vertex)
	defer delete(attribute_descriptions)

	vertex_input_state := core.vk_vertex_input_state_create({binding_description}, attribute_descriptions)

	vertex_module := core.vk_shader_module_create("./games/chain_reaction/engine/shaders/gourd.vert.spv")
	defer core.vk_shader_module_destroy(vertex_module)
	
	fragment_module := core.vk_shader_module_create("./games/chain_reaction/engine/shaders/gourd.frag.spv")
	defer core.vk_shader_module_destroy(fragment_module)

	color_blend_attachment_state := core.vk_color_blend_attachment_state_create()
	color_blend_state := core.vk_color_blend_state_create({color_blend_attachment_state})

	descriptor_types: [2+len(Texture_Type)]vk.DescriptorType
	descriptor_types[0] = .STORAGE_BUFFER
	descriptor_types[1] = .STORAGE_BUFFER
	for &type in descriptor_types[1:] do type = .COMBINED_IMAGE_SAMPLER

	descriptor_counts: [len(descriptor_types)]u32
	for &count in descriptor_counts do count = Frames_In_Flight

	descriptor_pool = core.vk_descriptor_pool_create(descriptor_types[:], descriptor_counts[:], Frames_In_Flight)

	layout_bindings: [len(descriptor_types)]vk.DescriptorSetLayoutBinding
	layout_bindings[0] = {
		binding         = 0,
		descriptorType  = .STORAGE_BUFFER,
		descriptorCount = 1,
		stageFlags      = {.VERTEX, .FRAGMENT}
	}
	layout_bindings[1] = {
		binding         = 1,
		descriptorType  = .STORAGE_BUFFER,
		descriptorCount = 1,
		stageFlags      = {.VERTEX, .FRAGMENT}
	}
	for i in 2..<len(descriptor_types) {
		layout_bindings[i] = {
			binding         = u32(i),
			descriptorType  = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			stageFlags      = {.FRAGMENT}
		}
	}

	descriptor_layout = core.vk_descriptor_set_layout_create(layout_bindings[:])
	descriptor_layouts: [Frames_In_Flight]vk.DescriptorSetLayout
	for &layout in descriptor_layouts do layout = descriptor_layout
	descriptor_sets = core.vk_descriptor_set_create(descriptor_pool, descriptor_layouts[:])

	input_assembly_state := core.vk_input_assembly_state_create()
	viewport_state       := core.vk_viewport_state_create()
	rasterizer_state     := core.vk_rasterizer_state_create()
	multisample_state    := core.vk_multisample_state_create()
	depth_stencil_state  := core.vk_depth_stencil_state_create()
	dynamic_state        := core.vk_dynamic_state_create()	
	
	pipeline, pipeline_layout = core.vk_graphics_pipeline_create(
		&rendering_info,
		&vertex_input_state,
		&input_assembly_state,
		&viewport_state,
		&rasterizer_state,
		&multisample_state,
		&depth_stencil_state,
		&color_blend_state,
		&dynamic_state,
		{
			core.vk_shader_stage_state_create({.VERTEX}, vertex_module, "main"),
			core.vk_shader_stage_state_create({.FRAGMENT}, fragment_module, "main"),
		},
		{descriptor_layout}
	)
	
	pixel_ubo = core.vk_uniform_buffer_create(size_of(Shader_Pixel_Data), &vk_allocator)

	pixel_sampler = core.vk_sampler_create()

	quad_vertices = {
		{
			position = {-1, -1, 0},
			uv       = {0, 0}
		},
		{
			position = {1, -1, 0},
			uv       = {1, 0}
		},
		{
			position = {1, 1, 0},
			uv       = {1, 1}
		},
		{
			position = {-1, 1, 0},
			uv       = {0, 1}
		}
	}

	quad_indices = {
		0, 1, 2,
		2, 3, 0
	}

	quad_vertex_buffer = core.vk_vertex_buffer_create(size_of(Vertex) * len(quad_vertices), &vk_allocator)

	core.vk_buffer_copy(transfer_pool, &quad_vertex_buffer, raw_data(quad_vertices[:]), &vk_allocator)
	
	quad_index_buffer = core.vk_index_buffer_create(size_of(u32) * len(quad_indices), &vk_allocator)
	
	core.vk_buffer_copy(transfer_pool, &quad_index_buffer, raw_data(quad_indices[:]), &vk_allocator)
	
	pixel_vertex_module := core.vk_shader_module_create("./games/chain_reaction/engine/shaders/gourd_pixel.vert.spv")
	defer core.vk_shader_module_destroy(pixel_vertex_module)
	
	pixel_fragment_module := core.vk_shader_module_create("./games/chain_reaction/engine/shaders/gourd_pixel.frag.spv")
	defer core.vk_shader_module_destroy(pixel_fragment_module)

	pixel_descriptor_pool = core.vk_descriptor_pool_create({.UNIFORM_BUFFER, .COMBINED_IMAGE_SAMPLER}, {Frames_In_Flight, Frames_In_Flight}, Frames_In_Flight)

	pixel_descriptor_layout = core.vk_descriptor_set_layout_create(
		{
			{
				binding         = 0,
				descriptorType  = .UNIFORM_BUFFER,
				descriptorCount = 1,
				stageFlags      = {.FRAGMENT}
			},
			{
				binding         = 1,
				descriptorType  = .COMBINED_IMAGE_SAMPLER,
				descriptorCount = 1,
				stageFlags      = {.FRAGMENT}
			}
		}
	)
	pixel_descriptor_layouts: [Frames_In_Flight]vk.DescriptorSetLayout
	for &layout in pixel_descriptor_layouts do layout = pixel_descriptor_layout
	
	pixel_descriptor_sets = core.vk_descriptor_set_create(pixel_descriptor_pool, pixel_descriptor_layouts[:])
	
	pixel_pipeline, pixel_pipeline_layout = core.vk_graphics_pipeline_create(
		&rendering_info,
		&vertex_input_state,
		&input_assembly_state,
		&viewport_state,
		&rasterizer_state,
		&multisample_state,
		nil,
		&color_blend_state,
		&dynamic_state,
		{
			core.vk_shader_stage_state_create({.VERTEX}, pixel_vertex_module, "main"),
			core.vk_shader_stage_state_create({.FRAGMENT}, pixel_fragment_module, "main"),
		},
		{pixel_descriptor_layout}
	)

	pixel_data.pixel_size = 8
	recreate_pipeline_images(core.vk_swapchain_get_extent())
	core.vk_swapchain_set_recreation_callback(recreate_pipeline_images)
	
	initialised = true
}

renderer_destroy :: proc() {
	using renderer
	ensure(initialised)

	core.vk_command_buffer_destroy(command_buffers)
	core.vk_command_pool_destroy(graphics_pool)
	core.vk_command_pool_destroy(transfer_pool)
	core.vk_semaphore_destroy(image_available)
	core.vk_semaphore_destroy(render_finished)
	core.vk_fence_destroy(block_until)
	
	core.vk_sampler_destroy(pixel_sampler)
	core.vk_buffer_destroy(&quad_vertex_buffer)
	core.vk_buffer_destroy(&quad_index_buffer)
	core.vk_buffer_destroy(&pixel_ubo)
	core.vk_descriptor_set_destroy(descriptor_pool, descriptor_sets[:])
	core.vk_descriptor_pool_destroy(descriptor_pool)
	core.vk_descriptor_set_layout_destroy(descriptor_layout)
	for sampler in samplers do core.vk_sampler_destroy(sampler)
	core.vk_buffer_destroy(&cold_ssbo)
	core.vk_image_destroy(&depth_image)
	core.vk_graphics_pipeline_destroy(pipeline, pipeline_layout)

	core.vk_image_destroy(&pixel_image)
	core.vk_descriptor_set_destroy(pixel_descriptor_pool, pixel_descriptor_sets[:])
	core.vk_descriptor_pool_destroy(pixel_descriptor_pool)
	core.vk_descriptor_set_layout_destroy(pixel_descriptor_layout)
	core.vk_graphics_pipeline_destroy(pixel_pipeline, pixel_pipeline_layout)
	
	initialised = false
}

renderer_set_pixelation :: proc(
	pixel_size: f32
) {
	using renderer
	pixel_data.pixel_size = pixel_size
	core.vk_buffer_copy(transfer_pool, &pixel_ubo, &pixel_data, &vk_allocator)
}

renderer_render_scene_swapchain :: proc(
	scene:  ^Scene,
	camera: ^core.Camera_3D
) {
	using renderer
	assert(scene != nil)
	assert(camera != nil)

	frame = (frame + 1) % Frames_In_Flight
	index := core.vk_swapchain_get_next_image_index(image_available[frame], block_until[frame])
	extent := core.vk_swapchain_get_extent()
	
	core.vk_command_buffer_reset(command_buffers[frame])
	core.vk_command_buffer_begin(command_buffers[frame])
	
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
			core.vk_color_attachment_create(pixel_image.view, clear_color = {0.0, 0.0, 0.0, 1})
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
}

@(private="file")
recreate_pipeline_images :: proc(
	extent: vk.Extent2D
) {
	using renderer

	if depth_image.handle != 0 do core.vk_image_destroy(&depth_image)

	depth_image = core.vk_depth_image_create(
		depth_format,
		.OPTIMAL,
		{
			width  = extent.width,
			height = extent.height,
			depth  = 1
		},
		{.DEPTH_STENCIL_ATTACHMENT},
		&vk_allocator
	)

	if pixel_image.handle != 0 do core.vk_image_destroy(&pixel_image)

	swapchain_format := core.vk_swapchain_get_image_format()
	
	pixel_image = core.vk_texture_image_create(
		.OPTIMAL,
		{
			width = extent.width,
			height = extent.height,
			depth = 1
		},
		swapchain_format,
		&vk_allocator
	)

	pixel_data.resolution = {f32(extent.width), f32(extent.height)}
	core.vk_buffer_copy(transfer_pool, &pixel_ubo, &pixel_data, &vk_allocator)
}
