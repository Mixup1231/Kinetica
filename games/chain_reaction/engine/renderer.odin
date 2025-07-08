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

Renderer :: struct {
	frame:             u32,
	graphics_pool:     core.VK_Command_Pool,
	transfer_pool:     core.VK_Command_Pool,
	command_buffers:   []core.VK_Command_Buffer,
	image_available:   []vk.Semaphore,
	render_finished:   []vk.Semaphore,
	block_until:       []vk.Fence,
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
	pipeline:          vk.Pipeline,
	pipeline_layout:   vk.PipelineLayout,
	vk_allocator:      core.VK_Allocator,

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
	recreate_depth_image(core.vk_swapchain_get_extent())
	core.vk_swapchain_set_recreation_callback(recreate_depth_image)

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
	core.vk_descriptor_set_destroy(descriptor_pool, descriptor_sets[:])
	core.vk_descriptor_pool_destroy(descriptor_pool)
	core.vk_descriptor_set_layout_destroy(descriptor_layout)
	for sampler in samplers do core.vk_sampler_destroy(sampler)
	core.vk_buffer_destroy(&cold_ssbo)
	core.vk_image_destroy(&depth_image)
	core.vk_graphics_pipeline_destroy(pipeline, pipeline_layout)
	
	initialised = false
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
		image           = core.vk_swapchain_get_image(index),
		dst_access_mask = {.COLOR_ATTACHMENT_WRITE},
		old_layout      = .UNDEFINED,
		new_layout      = .COLOR_ATTACHMENT_OPTIMAL,
		src_stage_mask  = {.TOP_OF_PIPE},
		dst_stage_mask  = {.COLOR_ATTACHMENT_OUTPUT},
	)	

	core.vk_command_image_barrier(
		command_buffers[frame],
		image             = &depth_image,
		dst_access_mask   = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
		old_layout        = .UNDEFINED,
		new_layout        = .DEPTH_ATTACHMENT_OPTIMAL,
		src_stage_mask    = {.TOP_OF_PIPE},
		dst_stage_mask    = {.EARLY_FRAGMENT_TESTS},
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
			core.vk_color_attachment_create(core.vk_swapchain_get_image_view(index))
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
	core.vk_command_descriptor_set_bind(command_buffers[frame], pipeline_layout, .GRAPHICS, descriptor_sets[frame])
	
	cold_data.view_projection = core.camera_3d_get_view_projection(camera)
	cold_data.camera_position = camera.position.xyzz
	cold_data.ambient_color = scene.ambient_color.xyzz
	cold_data.ambient_strength = scene.ambient_strength
	for i in 0..<scene.point_light_count do cold_data.point_lights[i] = scene.point_lights[i]
	cold_data.point_light_count = scene.point_light_count
	
	core.vk_buffer_copy(transfer_pool, &cold_ssbo, &cold_data, &vk_allocator)
	core.vk_descriptor_set_update_storage_buffer(descriptor_sets[frame], 0, &cold_ssbo)

	// NOTE(Mitchell): This is bugged, fix it
	instance_count, first_index: u32
	for mesh, &entity_array in scene.meshes {
		mesh_hot := resource_manager_get_mesh_hot(mesh)
		core.vk_command_vertex_buffers_bind(command_buffers[frame], {mesh_hot.vertex_buffer.handle})
		core.vk_command_index_buffer_bind(command_buffers[frame], mesh_hot.index_buffer.handle)
		// set texture types
		
		for entity_id in sparse_array_slice(&entity_array) {
			entity := sparse_array_get(&scene.entities, entity_id)
			hot_data.model_matrices[instance_count] = core.transform_get_matrix(&entity.transform)
			instance_count += 1
		}

		core.vk_buffer_copy(transfer_pool, &hot_ssbo, &hot_data, &vk_allocator)
		core.vk_descriptor_set_update_storage_buffer(descriptor_sets[frame], 1, &hot_ssbo)

		core.vk_command_draw_indexed(command_buffers[frame], mesh_hot.index_count, instance_count, first_index)
		first_index = instance_count - 1
	}

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
recreate_depth_image :: proc(
	extent: vk.Extent2D
) {
	using renderer

	if depth_image.handle != 0 do core.vk_image_destroy(&depth_image)

	depth_image = core.vk_depth_image_create(
		depth_format,
		.OPTIMAL,
		{
			width = extent.width,
			height = extent.height,
			depth = 1
		},
		{.DEPTH_STENCIL_ATTACHMENT},
		&vk_allocator
	)
}
