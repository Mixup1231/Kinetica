package core

import "core:os"
import "core:log"

import vk "vendor:vulkan"

// TODO(Mitchell):

Queue_Type :: enum {
	Graphics,
	Compute,
	Transfer,
	Present
}

vulkan_shader_module_create :: proc(
	filepath: cstring,
	allocator := context.allocator
) -> (
	shader_module: vk.ShaderModule
){
	context.allocator = allocator
	ensure(vk_context.initialised)

	shader_code, read_file := os.read_entire_file(string(filepath))
	if !read_file {
		log.warn("Vulkan - Shader: Failed to read shader file: %s", filepath)
		
		return shader_module
	}
	defer delete(shader_code)

	shader_module_create_info: vk.ShaderModuleCreateInfo = {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(shader_code),
		pCode    = transmute(^u32)raw_data(shader_code),
	}
	vk_warn(vk.CreateShaderModule(vk_context.device.logical, &shader_module_create_info, nil, &shader_module))

	return shader_module
}

vulkan_shader_module_destroy :: proc(
	shader_module: vk.ShaderModule
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	
	vk.DestroyShaderModule(vk_context.device.logical, shader_module, nil)
}

vulkan_shader_stage_state_create :: proc(
	stage:  vk.ShaderStageFlags = {},
	module: vk.ShaderModule     = 0,
	entry:  cstring             = "main"
) -> (
	shader_stage: vk.PipelineShaderStageCreateInfo
) {
	shader_stage = {
		sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = stage,
		module = module,
		pName  = entry
	}
	
	return shader_stage
}

vulkan_vertex_input_state_create :: proc(
	binding_descriptions:   []vk.VertexInputBindingDescription   = {},
	attribute_descriptions: []vk.VertexInputAttributeDescription = {}
) -> (
	vertex_input_state: vk.PipelineVertexInputStateCreateInfo
) {
	vertex_input_state = {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = u32(len(binding_descriptions)),
		pVertexBindingDescriptions      = raw_data(binding_descriptions),
		vertexAttributeDescriptionCount = u32(len(attribute_descriptions)),
		pVertexAttributeDescriptions    = raw_data(attribute_descriptions),
	}
	
	return vertex_input_state
}

vulkan_input_assembly_state_create :: proc(
	topology: vk.PrimitiveTopology = .TRIANGLE_LIST,
	restart:  b32                  = false
) -> (
	input_assembly_state: vk.PipelineInputAssemblyStateCreateInfo
) {
	input_assembly_state = {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = topology,
		primitiveRestartEnable = restart,
	}

	return input_assembly_state
}

vulkan_viewport_state_create :: proc(
	viewport_count: u32 = 1,
	scissor_count:  u32 = 1,
) -> (
	viewport_state: vk.PipelineViewportStateCreateInfo
) {
	viewport_state = {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = viewport_count,
		scissorCount  = scissor_count,
	}

	return viewport_state
}

vulkan_rasterizer_state_create :: proc(
	depth_clamp_enable:         b32              = false,
	rasterizer_discard_enable:  b32              = false,
	polygon_mode:               vk.PolygonMode   = .FILL,
	cull_mode:                  vk.CullModeFlags = {.BACK},
	front_face:                 vk.FrontFace     = .CLOCKWISE,
	depth_bias_enable:          b32              = false,
	depth_bias_constant_factor: f32              = 0,
	depth_bias_clamp:           f32              = 0,
	depth_bias_slope_factor:    f32              = 0,
	line_width:                 f32              = 1
) -> (
	rasterizer_state: vk.PipelineRasterizationStateCreateInfo
) {
	rasterizer_state = {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = depth_clamp_enable,
		rasterizerDiscardEnable = rasterizer_discard_enable,
		polygonMode             = polygon_mode,
		cullMode                = cull_mode,
		frontFace               = front_face,
		depthBiasEnable         = depth_bias_enable,
		depthBiasConstantFactor = depth_bias_constant_factor,
		depthBiasClamp          = depth_bias_clamp,
		depthBiasSlopeFactor    = depth_bias_slope_factor,
		lineWidth               = line_width,
	}
	
	return rasterizer_state
}

vulkan_multisample_state_create :: proc(
	rasterization_samples:    vk.SampleCountFlags = {._1},
	sample_shading_enable:    b32                 = false,
	min_sample_shading:       f32                 = 0,
	sample_mask:              ^vk.SampleMask      = nil,
	alpha_to_coverage_enable: b32                 = false,
	alpha_to_one_enable:      b32                 = false
) -> (
	multisample_state: vk.PipelineMultisampleStateCreateInfo
) {
	multisample_state = {
		sType                 = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples  = rasterization_samples,
		sampleShadingEnable   = sample_shading_enable,
		minSampleShading      = min_sample_shading,
		pSampleMask           = sample_mask,
		alphaToCoverageEnable = alpha_to_coverage_enable,
		alphaToOneEnable      = alpha_to_one_enable,
	}
	
	return multisample_state
}

vulkan_color_attachment_state_create :: proc(
	blend_enable:           b32                    = false,
	src_color_blend_factor: vk.BlendFactor         = vk.BlendFactor.SRC_ALPHA,
	dst_color_blend_factor: vk.BlendFactor         = vk.BlendFactor.ONE_MINUS_SRC_ALPHA,
	color_blend_op:         vk.BlendOp             = vk.BlendOp.ADD,
	src_alpha_blend_factor: vk.BlendFactor         = vk.BlendFactor.ONE,
	dst_alpha_blend_factor: vk.BlendFactor         = vk.BlendFactor.ZERO,
	alpha_blend_op:         vk.BlendOp             = vk.BlendOp.ADD,
	color_write_mask:       vk.ColorComponentFlags = {.R, .G, .B, .A}
) -> (
	attachment_state: vk.PipelineColorBlendAttachmentState
) {
	attachment_state = {
		blendEnable         = blend_enable,
		srcColorBlendFactor = src_color_blend_factor,
		dstColorBlendFactor = dst_color_blend_factor,
		colorBlendOp        = color_blend_op,
		srcAlphaBlendFactor = src_alpha_blend_factor,
		dstAlphaBlendFactor = dst_alpha_blend_factor,
		alphaBlendOp        = alpha_blend_op,
		colorWriteMask      = color_write_mask,
	}
	
	return attachment_state
}

vulkan_color_blend_state_create :: proc(
	logic_op_enable: b32                                    = false,
	logic_op:        vk.LogicOp                             = .COPY,
	attachments:     []vk.PipelineColorBlendAttachmentState = {},
	blend_constants: [4]f32                                 = {0, 0, 0, 0}
) -> (
	color_blend_state: vk.PipelineColorBlendStateCreateInfo
) {
	color_blend_state = {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = logic_op_enable,
		logicOp         = logic_op,
		attachmentCount = u32(len(attachments)),
		pAttachments    = raw_data(attachments),
		blendConstants  = blend_constants,
	}
	
	return color_blend_state
}

// NOTE(Mitchell): Needs to contain viewport and scissor
vulkan_dynamic_state_create :: proc(
	dynamic_states: []vk.DynamicState = {.VIEWPORT, .SCISSOR}
) -> (
	dynamic_state: vk.PipelineDynamicStateCreateInfo
) {		
	found_viewport: bool
	for state in dynamic_states do if state == .VIEWPORT do found_viewport = true
	ensure(found_viewport)
	
	found_scissor:  bool
	for state in dynamic_states do if state == .SCISSOR do found_scissor = true
	ensure(found_scissor)
	
	dynamic_state = {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamic_states)),
		pDynamicStates    = raw_data(dynamic_states)
	}
	
	return dynamic_state
}

vulkan_get_swapchain_color_format :: proc() -> (
	format: vk.Format
) {
	ensure(vk_context.initialised)
	ensure(vk_context.swapchain.initialised)

	return vk_context.swapchain.attributes.format.format
}

vulkan_rendering_info_create :: proc(
	view_mask:                 u32         = 0,
	color_attachment_formats:  []vk.Format = {},
	depth_attachment_format:   vk.Format   = vk.Format.UNDEFINED,
	stencil_attachment_format: vk.Format   = vk.Format.UNDEFINED
) -> (
	rendering_info: vk.PipelineRenderingCreateInfo
) {
	rendering_info = {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		viewMask                = view_mask,
		colorAttachmentCount    = u32(len(color_attachment_formats)),
		pColorAttachmentFormats = raw_data(color_attachment_formats),
		depthAttachmentFormat   = depth_attachment_format,
		stencilAttachmentFormat = stencil_attachment_format,
	}
	
	return rendering_info
}

vulkan_graphics_pipeline_create :: proc (
	rendering_info:       ^vk.PipelineRenderingCreateInfo,
	vertex_input_state:   ^vk.PipelineVertexInputStateCreateInfo   = nil,
	input_assembly_state: ^vk.PipelineInputAssemblyStateCreateInfo = nil,
	viewport_state:       ^vk.PipelineViewportStateCreateInfo      = nil,
	rasterizer_state:     ^vk.PipelineRasterizationStateCreateInfo = nil,
	multisample_state:    ^vk.PipelineMultisampleStateCreateInfo   = nil,
	color_blend_state:    ^vk.PipelineColorBlendStateCreateInfo    = nil,
	dynamic_state:        ^vk.PipelineDynamicStateCreateInfo       = nil,
	shader_stages:        []vk.PipelineShaderStageCreateInfo       = {},
	descriptor_layouts:   []vk.DescriptorSetLayout                 = {},
	push_constant_ranges: []vk.PushConstantRange                   = {}
) -> (
	pipeline: vk.Pipeline,
	pipeline_layout: vk.PipelineLayout
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	ensure(rendering_info != nil)
	
	pipeline_layout_create_info: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = u32(len(descriptor_layouts)),
		pSetLayouts            = raw_data(descriptor_layouts),
		pushConstantRangeCount = u32(len(push_constant_ranges)),
		pPushConstantRanges    = raw_data(push_constant_ranges),
	}
	vk_warn(vk.CreatePipelineLayout(vk_context.device.logical, &pipeline_layout_create_info, nil, &pipeline_layout))

	pipeline_create_info: vk.GraphicsPipelineCreateInfo = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = rendering_info,
		layout              = pipeline_layout,
		stageCount          = u32(len(shader_stages)),
		pStages             = raw_data(shader_stages),
		pVertexInputState   = vertex_input_state,
		pInputAssemblyState = input_assembly_state,
		pViewportState      = viewport_state,
		pRasterizationState = rasterizer_state,
		pMultisampleState   = multisample_state,
		pColorBlendState    = color_blend_state,
		pDynamicState       = dynamic_state,
	}
	vk_warn(vk.CreateGraphicsPipelines(vk_context.device.logical, 0, 1, &pipeline_create_info, nil, &pipeline))

	return pipeline, pipeline_layout
}

vulkan_graphics_pipeline_destroy :: proc(
	pipeline:        vk.Pipeline,
	pipeline_layout: vk.PipelineLayout
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	
	vk_warn(vk.DeviceWaitIdle(vk_context.device.logical))
	vk.DestroyPipelineLayout(vk_context.device.logical, pipeline_layout, nil)
	vk.DestroyPipeline(vk_context.device.logical, pipeline, nil)
}

vulkan_command_graphics_pipeline_bind :: #force_inline proc(
	command_buffer: vk.CommandBuffer,
	pipeline:       vk.Pipeline
) {
	vk.CmdBindPipeline(command_buffer, .GRAPHICS, pipeline)
}

vulkan_command_pool_create :: proc(
	queue_type: Queue_Type
) -> (
	command_pool: vk.CommandPool
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)

	command_pool_create_info: vk.CommandPoolCreateInfo = {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = vk_context.device.queue_indices[queue_type]
	}
	
	vk_warn(vk.CreateCommandPool(vk_context.device.logical, &command_pool_create_info, nil, &command_pool))

	return command_pool
}

vulkan_command_pool_destroy :: proc(
	command_pool: vk.CommandPool
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)

	vk.DestroyCommandPool(vk_context.device.logical, command_pool, nil)
}

vulkan_command_buffer_create :: proc {
	vulkan_command_buffer_create_single,
	vulkan_command_buffer_create_array,
}

vulkan_command_buffer_create_single :: proc(
	command_pool: vk.CommandPool,
	level:        vk.CommandBufferLevel = .PRIMARY
) -> (
	command_buffer: vk.CommandBuffer
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	ensure(command_pool != 0)

	allocate_info: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool,
		commandBufferCount = 1,
		level              = vk.CommandBufferLevel(level)
	}
	vk_warn(vk.AllocateCommandBuffers(vk_context.device.logical, &allocate_info, &command_buffer))

	return command_buffer
}

vulkan_command_buffer_create_array :: proc(
	command_pool: vk.CommandPool,
	level:        vk.CommandBufferLevel = .PRIMARY,
	$Count:       u32
) -> (
	command_buffers: [Count]vk.CommandBuffer
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	ensure(command_pool != 0)

	allocate_info: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool,
		commandBufferCount = Count,
		level              = vk.CommandBufferLevel(level)
	}
	vk_warn(vk.AllocateCommandBuffers(vk_context.device.logical, &allocate_info, raw_data(command_buffers[:])))

	return command_buffers
}

vulkan_command_buffer_reset :: proc(
	command_buffer: vk.CommandBuffer
) {
	vk_warn(vk.ResetCommandBuffer(command_buffer, {.RELEASE_RESOURCES}))
}

vulkan_command_buffer_begin :: proc(
	command_buffer: vk.CommandBuffer,
	flags:          vk.CommandBufferUsageFlags = {.ONE_TIME_SUBMIT}
) {
	begin_info: vk.CommandBufferBeginInfo = {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = flags
	}
	vk_warn(vk.BeginCommandBuffer(command_buffer, &begin_info))
}

vulkan_command_buffer_end :: proc(
	command_buffer: vk.CommandBuffer
) {
	vk_warn(vk.EndCommandBuffer(command_buffer))
}

vulkan_semaphore_create :: proc {
	vulkan_semaphore_create_single,
	vulkan_semaphore_create_array,
}

vulkan_semaphore_create_single :: proc() -> (
	semaphore: vk.Semaphore 
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)

	semaphore_create_info: vk.SemaphoreCreateInfo = { sType = .SEMAPHORE_CREATE_INFO }
	vk_warn(vk.CreateSemaphore(vk_context.device.logical, &semaphore_create_info, nil, &semaphore))

	return semaphore
}

vulkan_semaphore_create_array :: proc(
	$Count: u32
) -> (
	semaphores: [Count]vk.Semaphore
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)

	semaphore_create_info: vk.SemaphoreCreateInfo = { sType = .SEMAPHORE_CREATE_INFO }
	for i in 0..<Count do vk_warn(vk.CreateSemaphore(vk_context.device.logical, &semaphore_create_info, nil, &semaphores[i]))

	return semaphores
}

vulkan_semaphore_destroy :: proc{
	vulkan_semaphore_destroy_single,
	vulkan_semaphore_destroy_array,
}

vulkan_semaphore_destroy_single :: proc(
	semaphore: vk.Semaphore
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	
	vk_warn(vk.DeviceWaitIdle(vk_context.device.logical))
	vk.DestroySemaphore(vk_context.device.logical, semaphore, nil)
}

vulkan_semaphore_destroy_array :: proc(
	semaphores: [$Count]vk.Semaphore
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)

	vk_warn(vk.DeviceWaitIdle(vk_context.device.logical))
	for semaphore in semaphores do vk.DestroySemaphore(vk_context.device.logical, semaphore, nil)
}

vulkan_fence_create :: proc {
	vulkan_fence_create_single,
	vulkan_fence_create_array,
}

vulkan_fence_create_single :: proc(
	signaled: bool = true
) -> (
	fence: vk.Fence
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)

	fence_create_info: vk.FenceCreateInfo = {
		sType = .FENCE_CREATE_INFO,
		flags = {}
	}
	if signaled do fence_create_info.flags = {.SIGNALED}
	
	vk.CreateFence(vk_context.device.logical, &fence_create_info, nil, &fence)

	return fence
}

vulkan_fence_create_array :: proc(
	signaled: bool = true,
	$Count:   u32
) -> (
	fences: [Count]vk.Fence
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)

	fence_create_info: vk.FenceCreateInfo = {
		sType = .FENCE_CREATE_INFO,
		flags = {}
	}
	if signaled do fence_create_info.flags = {.SIGNALED}

	for i in 0..<Count do vk.CreateFence(vk_context.device.logical, &fence_create_info, nil, &fences[i])

	return fences
}

vulkan_fence_destroy :: proc{
	vulkan_fence_destroy_single,
	vulkan_fence_destroy_array,
}

vulkan_fence_destroy_single :: proc(
	fence: vk.Fence
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	
	vk_warn(vk.DeviceWaitIdle(vk_context.device.logical))
	vk.DestroyFence(vk_context.device.logical, fence, nil)
}

vulkan_fence_destroy_array :: proc(
	fences: [$Count]vk.Fence
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)

	vk_warn(vk.DeviceWaitIdle(vk_context.device.logical))
	for fence in fences do vk.DestroyFence(vk_context.device.logical, fence, nil)
}

vulkan_swapchain_get_next_image_index :: proc(
	signal_image_available: vk.Semaphore,
	block_until:            vk.Fence,
) -> (
	image_index: u32
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	ensure(vk_context.swapchain.initialised)

	block_until := block_until

	vk_warn(vk.WaitForFences(vk_context.device.logical, 1, &block_until, true, max(u64)))
	vk_warn(vk.ResetFences(vk_context.device.logical, 1, &block_until))

	result := vk.AcquireNextImageKHR(
		vk_context.device.logical,
		vk_context.swapchain.handle,
		max(u64),
		signal_image_available,
		0,
		&image_index
	)

	#partial switch (result) {
	case .SUCCESS:
		return image_index
	case .ERROR_OUT_OF_DATE_KHR, .SUBOPTIMAL_KHR:
		log.info("Vulkan - Swapchain: Need to recreate swapchain.")
		return image_index
	case:
		log.fatal("Vulkan - Swapchain: Failed to acquire next swapchain image, exiting...")
		os.exit(-1)
	}
}

vulkan_submit_to_queue :: proc(
	queue_type:      Queue_Type,
	command_buffer:  vk.CommandBuffer,
	signal_finished: vk.Semaphore          = 0,
	wait_for:        vk.Semaphore          = 0,
	wait_for_stages: vk.PipelineStageFlags = {},
	block_until:     vk.Fence              = 0,
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)

	command_buffer := command_buffer

	submit_info: vk.SubmitInfo = {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &command_buffer
	}

	if signal_finished != 0 {
		signal_finished := signal_finished
		submit_info.signalSemaphoreCount = 1
		submit_info.pSignalSemaphores    = &signal_finished
	}

	if wait_for != 0 {
		wait_for        := wait_for
		wait_for_stages := wait_for_stages
		submit_info.waitSemaphoreCount = 1
		submit_info.pWaitSemaphores    = &wait_for
		submit_info.pWaitDstStageMask  = &wait_for_stages
	}

	if block_until != 0 {
		block_until := block_until
		vk_warn(vk.QueueSubmit(vk_context.device.queues[queue_type], 1, &submit_info, block_until))
		vk_warn(vk.WaitForFences(vk_context.device.logical, 1, &block_until, true, max(u64)))
	} else {
		vk_warn(vk.QueueSubmit(vk_context.device.queues[queue_type], 1, &submit_info, 0))
		vk_warn(vk.QueueWaitIdle(vk_context.device.queues[queue_type]))
	}
}

vulkan_present :: proc(
	wait_render_finished: vk.Semaphore,
	image_index:          u32,
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	ensure(vk_context.swapchain.initialised)

	wait_render_finished := wait_render_finished
	image_index          := image_index

	present_info: vk.PresentInfoKHR = {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &wait_render_finished,
		swapchainCount     = 1,
		pSwapchains        = &vk_context.swapchain.handle,
		pImageIndices      = &image_index
	}

	result := vk.QueuePresentKHR(vk_context.device.queues[.Present], &present_info)

	#partial switch (result) {
	case .SUCCESS:
		return
	case .ERROR_OUT_OF_DATE_KHR, .SUBOPTIMAL_KHR:
		log.info("Vulkan - Swapchain: Need to recreate swapchain")
	case:
		log.fatal("Vulkan - Queue: Failed to present to queue, exiting...")
		os.exit(-1)
	}
}

vulkan_command_viewport_set :: proc(
	command_buffer: vk.CommandBuffer,
	viewports:      []vk.Viewport
) {
	vk.CmdSetViewport(command_buffer, 0, u32(len(viewports)), raw_data(viewports))
}

vulkan_command_scissor_set :: proc(
	command_buffer: vk.CommandBuffer,
	scissors:       []vk.Rect2D
) {
	vk.CmdSetScissor(command_buffer, 0, u32(len(scissors)), raw_data(scissors))
}

vulkan_swapchain_image_get :: proc(
	index: u32
) -> (
	image: vk.Image
) {
	ensure(vk_context.initialised)
	ensure(vk_context.swapchain.initialised)
	ensure(index < u32(len(vk_context.swapchain.images)))

	return vk_context.swapchain.images[index]
}

vulkan_swapchain_image_view_get :: proc(
	index: u32
) -> (
	image: vk.ImageView
) {
	ensure(vk_context.initialised)
	ensure(vk_context.swapchain.initialised)
	ensure(index < u32(len(vk_context.swapchain.image_views)))

	return vk_context.swapchain.image_views[index]
}

vulkan_command_image_barrier :: proc(
	command_buffer:    vk.CommandBuffer,
	image:             vk.Image,
	src_access_mask:   vk.AccessFlags           = {},
	dst_access_mask:   vk.AccessFlags           = {},
	old_layout:        vk.ImageLayout           = .UNDEFINED,
	new_layout:        vk.ImageLayout           = .UNDEFINED,
	subresource_range: vk.ImageSubresourceRange = {{.COLOR}, 0, 1, 0, 1},
	src_stage_mask:    vk.PipelineStageFlags    = {},
	dst_stage_mask:    vk.PipelineStageFlags    = {}
) {
	ensure(vk_context.initialised)

	barrier: vk.ImageMemoryBarrier = {
		sType            = .IMAGE_MEMORY_BARRIER,
		dstAccessMask    = dst_access_mask,
		srcAccessMask    = src_access_mask,
		oldLayout        = old_layout,
		newLayout        = new_layout,
		image            = image,
		subresourceRange = subresource_range
	}

	vk.CmdPipelineBarrier(
		command_buffer,
		src_stage_mask,
		dst_stage_mask,
		{},
		0, nil,
		0, nil,
		1, &barrier
	)
}

vulkan_command_draw :: #force_inline proc(
	command_buffer: vk.CommandBuffer,
	vertex_count:   u32,
	instance_count: u32 = 1,
	first_vertex:   u32 = 0,
	first_instance: u32 = 0
) {
	vk.CmdDraw(command_buffer, vertex_count, instance_count, first_vertex, first_instance)
}

vulkan_command_end_rendering :: #force_inline proc(
	command_buffer: vk.CommandBuffer
) {
	vk.CmdEndRendering(command_buffer)
}

vulkan_color_attachment_create :: proc(
	image_view:  vk.ImageView,
	load_op:     vk.AttachmentLoadOp  = .CLEAR,
	store_op:    vk.AttachmentStoreOp = .STORE,
	clear_color: [4]f32               = {0, 0, 0, 0},
) -> (
	color_attachment: vk.RenderingAttachmentInfo
) {
	clear_value: vk.ClearValue
	clear_value.color.float32 = clear_color
	
	color_attachment = {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = image_view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = load_op,
		storeOp     = store_op,
		clearValue  = clear_value
	}

	return color_attachment
}

vulkan_command_begin_rendering :: proc(
	command_buffer:     vk.CommandBuffer,
	render_area:        vk.Rect2D,
	layer_count:        u32                          = 1,
	view_mask:          u32                          = 0,
	color_attachments:  []vk.RenderingAttachmentInfo = {},
	depth_attachment:   ^vk.RenderingAttachmentInfo  = nil,
	stencil_attachment: ^vk.RenderingAttachmentInfo  = nil,
) {	
	rendering_info: vk.RenderingInfo = {
		sType                = .RENDERING_INFO,
		renderArea           = render_area,
		layerCount           = layer_count,
		colorAttachmentCount = u32(len(color_attachments)),
		pColorAttachments    = raw_data(color_attachments),
		pDepthAttachment     = depth_attachment,
		pStencilAttachment   = stencil_attachment,
	}

	vk.CmdBeginRendering(command_buffer, &rendering_info)
}
