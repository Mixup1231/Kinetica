package core

import "core:os"
import "core:log"

import vk "vendor:vulkan"

// handles
Shader_Module          :: vk.ShaderModule
Descriptor_Set         :: vk.DescriptorSetLayout
Descriptor_Pool        :: vk.DescriptorPool
Dynamic_State          :: vk.DynamicState
Color_Blend_Attachment :: vk.PipelineColorBlendAttachmentState
Pipeline_Layout_Handle :: vk.PipelineLayout
Pipeline_Handle        :: vk.Pipeline
Command_Pool           :: vk.CommandPool
Command_Buffer         :: vk.CommandBuffer

// struct aliases
Dynamic_State_Info       :: vk.PipelineDynamicStateCreateInfo
Vertex_Input_Info        :: vk.PipelineVertexInputStateCreateInfo
Input_Assembly_Info      :: vk.PipelineInputAssemblyStateCreateInfo
Viewport_State_Info      :: vk.PipelineViewportStateCreateInfo
Rasterization_State_Info :: vk.PipelineRasterizationStateCreateInfo
Multisample_State_Info   :: vk.PipelineMultisampleStateCreateInfo
Color_Blend_State_Info   :: vk.PipelineColorBlendStateCreateInfo

// enums
Queue_Type :: enum {
	Graphics,
	Compute,
	Transfer,
	Present,
}

Shader_Stage_Types :: distinct bit_set[Shader_Stage_Type]
Shader_Stage_Type :: enum(vk.Flags) {
	Vertex   = vk.Flags(vk.ShaderStageFlag.VERTEX),
	Fragment = vk.Flags(vk.ShaderStageFlag.FRAGMENT),
	Compute  = vk.Flags(vk.ShaderStageFlag.COMPUTE),
	Geometry = vk.Flags(vk.ShaderStageFlag.GEOMETRY),
}

Descriptor_Type :: enum(i32) {
	Sampler        = i32(vk.DescriptorType.SAMPLER),
	Uniform_Buffer = i32(vk.DescriptorType.UNIFORM_BUFFER),
	Storage_Buffer = i32(vk.DescriptorType.STORAGE_BUFFER),
}

Primitive_Topology :: enum(i32) {
	Point_List     = i32(vk.PrimitiveTopology.POINT_LIST),
	Line_List      = i32(vk.PrimitiveTopology.LINE_LIST),
	Line_Strip     = i32(vk.PrimitiveTopology.LINE_STRIP),
	Triangle_List  = i32(vk.PrimitiveTopology.TRIANGLE_LIST),
	Triangle_Strip = i32(vk.PrimitiveTopology.TRIANGLE_STRIP),
	Triangle_Fan   = i32(vk.PrimitiveTopology.TRIANGLE_FAN),
}

Polygon_Mode :: enum(i32) {
	Fill  = i32(vk.PolygonMode.FILL),
	Line  = i32(vk.PolygonMode.LINE),
	Point = i32(vk.PolygonMode.POINT),
}

Cull_Modes :: distinct bit_set[Cull_Mode]
Cull_Mode :: enum(i32) {
	Back  = i32(vk.CullModeFlag.BACK),
	Front = i32(vk.CullModeFlag.FRONT),
}

Front_Face :: enum(i32) {
	Clockwise         = i32(vk.FrontFace.CLOCKWISE),
	Counter_Clockwise = i32(vk.FrontFace.COUNTER_CLOCKWISE),
}

Command_Buffer_Level :: enum(i32) {
	Primary   = i32(vk.CommandBufferLevel.PRIMARY),
	Secondary = i32(vk.CommandBufferLevel.SECONDARY),
}

// structs
Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
	uv:       [2]f32,
}

Shader_Stage :: struct {
	module:      Shader_Module,
	stage:       Shader_Stage_Types,
	entry_point: cstring,
}

Descriptor_Set_Binding :: struct {
	binding: u32,
	type:    Descriptor_Type,
	count:   u32,
	stages:  Shader_Stage_Types,
}

Shader :: struct {
	shader_stages:   []Shader_Stage,
	descriptor_sets: []Descriptor_Set,
}

Pipeline_Layout_Attributes :: struct {
	viewport_count: u32,
	scissor_count:  u32,
	polygon_mode:   Polygon_Mode,
	cull_mode:      Cull_Modes,
	front_face:     Front_Face,
	topology:       Primitive_Topology
}

Pipeline_Layout :: struct {
	handle:                   Pipeline_Layout_Handle,
	shader:                   Shader,
	dynamic_state:            []Dynamic_State,
	dynamic_state_info:       Dynamic_State_Info,
	vertex_input_info:        Vertex_Input_Info,
	input_assembly_info:      Input_Assembly_Info, 
	viewport_state_info:      Viewport_State_Info,
	rasterization_state_info: Rasterization_State_Info,
	multisample_state_info:   Multisample_State_Info,
	color_blend_attachment:   Color_Blend_Attachment,
	color_blend_state_info:   Color_Blend_State_Info,
}

Pipeline :: struct {
	handle: Pipeline_Handle,
	layout: Pipeline_Layout
}

shader_stage_create :: proc(
	filepath:    cstring,
	entry_point: cstring,
	stage:       Shader_Stage_Types,
	allocator := context.allocator
) -> (
	shader_stage: Shader_Stage
) {
	context.allocator = allocator
	ensure(vk_context.initialised)

	shader_stage = {
		module      = Shader_Module(vulkan_create_shader_module(vk_context.device.logical, filepath)),
		stage       = stage,
		entry_point = entry_point
	}

	return shader_stage
}

shader_stage_destroy :: proc(
	shader_stage: Shader_Stage
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	ensure(shader_stage.module != 0)

	vk.DestroyShaderModule(vk_context.device.logical, shader_stage.module, nil)
}

descriptor_set_create :: proc(
	descriptor_bindings: []Descriptor_Set_Binding,
	allocator := context.allocator
) -> (
	descriptor_set: Descriptor_Set
) {
	context.allocator = allocator
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)

	binding_count := u32(len(descriptor_bindings))
	ensure(binding_count > 0)

	binding_layouts := make([]vk.DescriptorSetLayoutBinding, binding_count)
	defer delete(binding_layouts)

	for descriptor_binding, i in descriptor_bindings {
		binding_layouts[i] = {
			binding         = descriptor_binding.binding,
			descriptorType  = vk.DescriptorType(descriptor_binding.type),
			descriptorCount = descriptor_binding.count,
		}

		for stage in descriptor_binding.stages do binding_layouts[i].stageFlags += {vk.ShaderStageFlag(stage)}
	}

	descriptor_set_layout_create_info: vk.DescriptorSetLayoutCreateInfo = {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = binding_count,
		pBindings    = raw_data(binding_layouts)
	}

	vk_warn(vk.CreateDescriptorSetLayout(
		vk_context.device.logical,
		&descriptor_set_layout_create_info,
		nil,
		&descriptor_set
	))

	return descriptor_set
}

descriptor_set_destroy :: proc(
	descriptor_set: Descriptor_Set
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)

	vk.DestroyDescriptorSetLayout(vk_context.device.logical, descriptor_set, nil)
}

// TODO(Mitchell): Consider making a Pipeline_Layout_Attributes struct to make things configurable
pipeline_layout_create :: proc(
	shader:                     Shader,
	pipeline_layout_attributes: Pipeline_Layout_Attributes,
	allocator := context.allocator
) -> (
	pipeline_layout: Pipeline_Layout
) {
	context.allocator = allocator
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	ensure(vk_context.swapchain.initialised)

	pipeline_layout.dynamic_state = make([]Dynamic_State, 2)
	pipeline_layout.dynamic_state[0] = .VIEWPORT
	pipeline_layout.dynamic_state[1] = .SCISSOR

	pipeline_layout.dynamic_state_info = {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(pipeline_layout.dynamic_state)),
		pDynamicStates    = raw_data(pipeline_layout.dynamic_state),
	}
	
	// NOTE(Mitchell): I'm assuming this will need to be configurable for VR
	pipeline_layout.viewport_state_info = {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = pipeline_layout_attributes.viewport_count,
		scissorCount  = pipeline_layout_attributes.scissor_count,
	}

	pipeline_layout.vertex_input_info = {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}

	pipeline_layout.input_assembly_info  = {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = vk.PrimitiveTopology(pipeline_layout_attributes.topology)
	}

	pipeline_layout.rasterization_state_info = {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = vk.PolygonMode(pipeline_layout_attributes.polygon_mode),
		lineWidth   = 1,
		frontFace   = vk.FrontFace(pipeline_layout_attributes.front_face),
	}

	for order in pipeline_layout_attributes.cull_mode do pipeline_layout.rasterization_state_info.cullMode += {vk.CullModeFlag(order)}

	// NOTE(Mitchell): May be worth looking into this more
	pipeline_layout.multisample_state_info  = {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
		minSampleShading     = 1
	}

	pipeline_layout.color_blend_attachment = {
		colorWriteMask = {.R, .G, .B, .A},
		blendEnable    = false
	}

	pipeline_layout.color_blend_state_info  = {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &pipeline_layout.color_blend_attachment
	}

	// TODO(Mitchell): Implement push constant support
	pipeline_layout_create_info: vk.PipelineLayoutCreateInfo = {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = u32(len(shader.descriptor_sets)),
		pSetLayouts = raw_data(shader.descriptor_sets)
	}

	pipeline_layout.shader = shader

	vk_warn(vk.CreatePipelineLayout(vk_context.device.logical, &pipeline_layout_create_info, nil, &pipeline_layout.handle))

	return pipeline_layout
}

pipeline_layout_destroy :: proc(
	pipeline_layout: Pipeline_Layout
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)

	vk.DestroyPipelineLayout(vk_context.device.logical, pipeline_layout.handle, nil)
	delete(pipeline_layout.dynamic_state)
}

pipeline_create :: proc(
	pipeline_layout: Pipeline_Layout,
	allocator := context.allocator
) -> (
	pipeline: Pipeline
) {
	context.allocator = allocator
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	ensure(vk_context.swapchain.initialised)
	ensure(pipeline_layout.handle != 0)

	pipeline_layout := pipeline_layout
	pipeline.layout = pipeline_layout

	shader_stage_infos := make([]vk.PipelineShaderStageCreateInfo, len(pipeline_layout.shader.shader_stages))
	defer delete(shader_stage_infos)
	
	for shader_stage, i in pipeline_layout.shader.shader_stages {
		shader_stage_infos[i] = {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			module = shader_stage.module,
			pName  = shader_stage.entry_point
		}

		for stage in shader_stage.stage do shader_stage_infos[i].stage += {vk.ShaderStageFlag(stage)}
	}

	rendering_create_info: vk.PipelineRenderingCreateInfo = {
		sType = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount = 1,
		pColorAttachmentFormats = &vk_context.swapchain.attributes.format.format,	
	}

	// TODO(Mitchell): Will want to provide functionality to derive pipelines
	pipeline_create_info: vk.GraphicsPipelineCreateInfo = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &rendering_create_info,
		layout              = pipeline_layout.handle,
		stageCount          = u32(len(pipeline_layout.shader.shader_stages)),
		pStages             = raw_data(shader_stage_infos),
		pVertexInputState   = &pipeline_layout.vertex_input_info,
		pInputAssemblyState = &pipeline_layout.input_assembly_info,
		pViewportState      = &pipeline_layout.viewport_state_info,
		pRasterizationState = &pipeline_layout.rasterization_state_info,
		pMultisampleState   = &pipeline_layout.multisample_state_info,
		pColorBlendState    = &pipeline_layout.color_blend_state_info,
		pDynamicState       = &pipeline_layout.dynamic_state_info,
	}

	vk_warn(vk.CreateGraphicsPipelines(vk_context.device.logical, 0, 1, &pipeline_create_info, nil, &pipeline.handle))

	return pipeline
}

pipeline_destroy :: proc(
	pipeline: Pipeline
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)

	vk.DestroyPipeline(vk_context.device.logical, pipeline.handle, nil)
	pipeline_layout_destroy(pipeline.layout)
	for shader_stage in pipeline.layout.shader.shader_stages do shader_stage_destroy(shader_stage)
	for descriptor_set in pipeline.layout.shader.descriptor_sets do descriptor_set_destroy(descriptor_set)
}

// NOTE(Mitchell): Will always use RESET bit, may want to make configurable
command_pool_create :: proc(
	queue_type: Queue_Type
) -> (
	command_pool: Command_Pool
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)

	command_pool_create_info: vk.CommandPoolCreateInfo = {
		sType = .COMMAND_POOL_CREATE_INFO,
		flags = {.RESET_COMMAND_BUFFER},
	}

	switch (queue_type) {
	case .Graphics: command_pool_create_info.queueFamilyIndex = vk_context.device.queue_indices[.Graphics]
	case .Compute: command_pool_create_info.queueFamilyIndex  = vk_context.device.queue_indices[.Compute]
	case .Transfer: command_pool_create_info.queueFamilyIndex = vk_context.device.queue_indices[.Transfer]
	case .Present: command_pool_create_info.queueFamilyIndex  = vk_context.device.queue_indices[.Present]
	}

	vk.CreateCommandPool(vk_context.device.logical, &command_pool_create_info, nil, &command_pool)

	return command_pool
}

command_pool_destroy :: proc(
	command_pool: Command_Pool
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	ensure(command_pool != 0)

	vk.DestroyCommandPool(vk_context.device.logical, command_pool, nil)
}

command_buffer_create :: proc {
	command_buffer_create_single,
	command_buffer_create_array,
}

command_buffer_create_single :: proc(
	command_pool:         Command_Pool,
	command_buffer_level: Command_Buffer_Level
) -> (
	command_buffer: Command_Buffer
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	ensure(command_pool != 0)
	
	command_buffer_allocate_info: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool,
		level              = vk.CommandBufferLevel(command_buffer_level),
		commandBufferCount = 1
	}

	vk_warn(vk.AllocateCommandBuffers(vk_context.device.logical, &command_buffer_allocate_info, &command_buffer))

	return command_buffer
}

command_buffer_create_array :: proc(
	command_pool:         Command_Pool,
	command_buffer_level: Command_Buffer_Level,
	$Count:               u32
) -> (
	command_buffers: [Count]Command_Buffer
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	ensure(command_pool != 0)
	
	command_buffer_allocate_info: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool,
		level              = vk.CommandBufferLevel(command_buffer_level),
		commandBufferCount = Count
	}

	vk_warn(vk.AllocateCommandBuffers(vk_context.device.logical, &command_buffer_allocate_info, &command_buffers[0]))

	return command_buffers
}
