package core

import "core:os"
import "core:log"
import "core:mem"
import "core:math"
import "core:reflect"

import vk "vendor:vulkan"

// TODO(Mitchell):
// Create VK_Graphics_Pipeline
// Create VK_Arena
// Create stencil rendering attachment create

VK_Queue_Types :: distinct bit_set[VK_Queue_Type]
VK_Queue_Type :: enum {
	Graphics,
	Compute,
	Transfer,
	Present
}

VK_Memory_Map_Type :: enum {
	Never,
	Always,
	Toggle,
}

VK_Allocate_Info :: struct {
	memory_info:     vk.MemoryAllocateInfo,
	memory_flags:    vk.MemoryAllocateFlags,
	memory_map_type: VK_Memory_Map_Type,
}

VK_Allocation :: struct {
	type_index: u32,
	handle:     vk.DeviceMemory,
	size:       vk.DeviceSize,
	offset:     vk.DeviceSize,
	id:         int,    // block id in pool allocator
	data:       rawptr, // cpu memory if mapped
}

VK_Allocator :: struct {
	allocate:   proc(^VK_Allocator, ^VK_Allocate_Info) -> VK_Allocation,
	deallocate: proc(^VK_Allocator, ^VK_Allocation),
}

VK_Command_Pool :: struct {
	handle:     vk.CommandPool,
	queue_type: VK_Queue_Type,
}

VK_Command_Buffer :: struct {
	handle:       vk.CommandBuffer,
	command_pool: VK_Command_Pool,
}

VK_Buffer :: struct {
	handle:       vk.Buffer,
	size:         vk.DeviceSize,
	allocation:   VK_Allocation,
	vk_allocator: ^VK_Allocator,
}

VK_Image :: struct {
	handle:            vk.Image,
	view:              vk.ImageView,
	format:            vk.Format,
	extent:            vk.Extent3D,
	subresource_range: vk.ImageSubresourceRange,
	allocation:        VK_Allocation,
	vk_allocator:      ^VK_Allocator,
}

vk_allocate_default :: proc(
	allocator:     ^VK_Allocator,
	allocate_info: ^VK_Allocate_Info
) -> (
	allocation: VK_Allocation
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(allocator != nil)
	assert(allocate_info != nil)
	
	allocation = {
		type_index = allocate_info.memory_info.memoryTypeIndex,
		size       = allocate_info.memory_info.allocationSize,
		offset     = 0
	}	
	vk_fatal(vk.AllocateMemory(vk_context.device.logical, &allocate_info.memory_info, nil, &allocation.handle))

	if allocate_info.memory_map_type == .Always {
		vk_warn(vk.MapMemory(vk_context.device.logical, allocation.handle, allocation.offset, allocation.size, {}, &allocation.data))
	}
	
	return allocation
}

vk_deallocate_default :: proc(
	allocator:  ^VK_Allocator,
	allocation: ^VK_Allocation
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(allocator != nil)
	assert(allocation != nil)

	vk.FreeMemory(vk_context.device.logical, allocation.handle, nil)
}

vk_allocator_get_default :: proc() -> (
	default_allocator: VK_Allocator
) {
	return {
		allocate   = vk_allocate_default,
		deallocate = vk_deallocate_default
	}
}

vk_shader_module_create :: proc(
	filepath: cstring,
	allocator := context.allocator
) -> (
	shader_module: vk.ShaderModule
){
	context.allocator = allocator
	assert(vk_context.initialised)

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

vk_shader_module_destroy :: proc(
	shader_module: vk.ShaderModule
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	
	vk.DestroyShaderModule(vk_context.device.logical, shader_module, nil)
}

vk_descriptor_pool_create :: proc(
	descriptor_types:  []vk.DescriptorType,
	descriptor_counts: []u32,
	max_sets:          u32,
	allocator := context.allocator
) -> (
	descriptor_pool: vk.DescriptorPool
) {
	context.allocator = allocator
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	type_count := len(descriptor_types)
	assert(type_count == len(descriptor_counts))

	pool_sizes := make([]vk.DescriptorPoolSize, type_count)
	defer delete(pool_sizes)
	
	for &pool_size, i in pool_sizes {
		pool_size = {
			type            = descriptor_types[i],
			descriptorCount = descriptor_counts[i]
		}
	}

	descriptor_pool_create_info: vk.DescriptorPoolCreateInfo = {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		flags         = {.FREE_DESCRIPTOR_SET},
		poolSizeCount = u32(type_count),
		pPoolSizes    = raw_data(pool_sizes),
		maxSets       = max_sets
	}
	vk_warn(vk.CreateDescriptorPool(vk_context.device.logical, &descriptor_pool_create_info, nil, &descriptor_pool))

	return descriptor_pool
}

vk_descriptor_pool_destroy :: proc(
	descriptor_pool: vk.DescriptorPool
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	
	vk.DestroyDescriptorPool(vk_context.device.logical, descriptor_pool, nil)
}

vk_descriptor_set_layout_create :: proc(
	bindings: []vk.DescriptorSetLayoutBinding,
	flags:    vk.DescriptorSetLayoutCreateFlags = {}
) -> (
	descriptor_set_layout: vk.DescriptorSetLayout
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	descriptor_set_layout_create_info: vk.DescriptorSetLayoutCreateInfo = {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		flags        = flags,
		bindingCount = u32(len(bindings)),
		pBindings    = raw_data(bindings)
	}
	vk_warn(vk.CreateDescriptorSetLayout(vk_context.device.logical, &descriptor_set_layout_create_info, nil, &descriptor_set_layout))

	return descriptor_set_layout
}

vk_descriptor_set_layout_destroy :: proc(
	descriptor_layout: vk.DescriptorSetLayout
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	
	vk.DestroyDescriptorSetLayout(vk_context.device.logical, descriptor_layout, nil)
}

vk_descriptor_set_create :: proc {
	vk_descriptor_set_create_single,
	vk_descriptor_set_create_slice,
}

vk_descriptor_set_create_single :: proc(
	descriptor_pool:   vk.DescriptorPool,
	descriptor_layout: vk.DescriptorSetLayout
) -> (
	descriptor_set: vk.DescriptorSet
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	descriptor_layout := descriptor_layout 

	descriptor_set_allocate_info: vk.DescriptorSetAllocateInfo = {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = descriptor_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &descriptor_layout
	}
	vk_warn(vk.AllocateDescriptorSets(vk_context.device.logical, &descriptor_set_allocate_info, &descriptor_set))

	return descriptor_set
}

vk_descriptor_set_create_slice :: proc(
	descriptor_pool:    vk.DescriptorPool,
	descriptor_layouts: []vk.DescriptorSetLayout,
	allocator := context.allocator
) -> (
	descriptor_sets: []vk.DescriptorSet
) {
	context.allocator = allocator
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	layout_count := u32(len(descriptor_layouts))
	descriptor_sets = make([]vk.DescriptorSet, layout_count)

	descriptor_set_allocate_info: vk.DescriptorSetAllocateInfo = {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = descriptor_pool,
		descriptorSetCount = layout_count,
		pSetLayouts        = raw_data(descriptor_layouts)
	}
	vk_warn(vk.AllocateDescriptorSets(vk_context.device.logical, &descriptor_set_allocate_info, raw_data(descriptor_sets)))

	return descriptor_sets
}

vk_descriptor_set_destroy :: proc {
	vk_descriptor_set_destroy_single,
	vk_descriptor_set_destroy_slice,
}

vk_descriptor_set_destroy_single :: proc(
	descriptor_pool: vk.DescriptorPool,
	descriptor_set:  vk.DescriptorSet
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	descriptor_set := descriptor_set
	
	vk.FreeDescriptorSets(vk_context.device.logical, descriptor_pool, 1, &descriptor_set)
}

vk_descriptor_set_destroy_slice :: proc(
	descriptor_pool: vk.DescriptorPool,
	descriptor_sets: []vk.DescriptorSet
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	
	vk.FreeDescriptorSets(vk_context.device.logical, descriptor_pool, u32(len(descriptor_sets)), raw_data(descriptor_sets))
	delete(descriptor_sets)
}

vk_command_descriptor_set_bind :: proc(
	command_buffer:  VK_Command_Buffer,
	pipeline_layout: vk.PipelineLayout,
	bind_point:      vk.PipelineBindPoint,
	descriptor_set:  vk.DescriptorSet
) {
	descriptor_set := descriptor_set

	vk.CmdBindDescriptorSets(command_buffer.handle, bind_point, pipeline_layout, 0, 1, &descriptor_set, 0, nil)
}

vk_descriptor_set_update_uniform_buffer :: proc(
	descriptor_set: vk.DescriptorSet,
	binding:        u32,
	uniform_buffer: ^VK_Buffer,
	offset:         vk.DeviceSize = 0,     
	array_element:  u32           = 0
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(uniform_buffer != nil)

	descriptor_buffer_info: vk.DescriptorBufferInfo = {
		buffer = uniform_buffer.handle,
		offset = offset,
		range  = uniform_buffer.size
	}

	write_desriptor_set: vk.WriteDescriptorSet = {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = descriptor_set,
		dstBinding      = binding,
		dstArrayElement = array_element,
		descriptorCount = 1,
		descriptorType  = .UNIFORM_BUFFER,
		pBufferInfo     = &descriptor_buffer_info
	}
	vk.UpdateDescriptorSets(vk_context.device.logical, 1, &write_desriptor_set, 0, nil)
}

vk_descriptor_set_update_storage_buffer :: proc(
	descriptor_set: vk.DescriptorSet,
	binding:        u32,
	storage_buffer: ^VK_Buffer,
	offset:         vk.DeviceSize = 0,     
	array_element:  u32           = 0
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(storage_buffer != nil)

	descriptor_buffer_info: vk.DescriptorBufferInfo = {
		buffer = storage_buffer.handle,
		offset = offset,
		range  = storage_buffer.size
	}

	write_desriptor_set: vk.WriteDescriptorSet = {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = descriptor_set,
		dstBinding      = binding,
		dstArrayElement = array_element,
		descriptorCount = 1,
		descriptorType  = .STORAGE_BUFFER,
		pBufferInfo     = &descriptor_buffer_info
	}
	vk.UpdateDescriptorSets(vk_context.device.logical, 1, &write_desriptor_set, 0, nil)
}

vk_descriptor_set_update_image :: proc(
	descriptor_set: vk.DescriptorSet,
	binding:        u32,
	image:          ^VK_Image,
	sampler:        vk.Sampler,
	offset:         vk.DeviceSize = 0,     
	array_element:  u32           = 0
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	
	descriptor_image_info: vk.DescriptorImageInfo = {
		sampler     = sampler,
		imageView   = image.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}

	write_descriptor_set: vk.WriteDescriptorSet = {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = descriptor_set,
		dstBinding      = binding,
		dstArrayElement = array_element,
		descriptorCount = 1,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		pImageInfo      = &descriptor_image_info
	}
	vk.UpdateDescriptorSets(vk_context.device.logical, 1, &write_descriptor_set, 0, nil)
}

vk_shader_stage_state_create :: proc(
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

vk_vertex_input_state_create :: proc(
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

vk_input_assembly_state_create :: proc(
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

vk_viewport_state_create :: proc(
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

vk_rasterizer_state_create :: proc(
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

vk_multisample_state_create :: proc(
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

vk_color_blend_attachment_state_create :: proc(
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

vk_color_blend_state_create :: proc(
	attachments:     []vk.PipelineColorBlendAttachmentState = {},
	logic_op_enable: b32                                    = false,
	logic_op:        vk.LogicOp                             = .COPY,
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

// NOTE(Mitchell): Review reverse depth buffering
vk_depth_stencil_state_create :: proc(
	depth_test_enable:        b32                                     = true,
	depth_write_enable:       b32                                     = true,
	depth_compare_op:         vk.CompareOp                            = .LESS,
	flags:                    vk.PipelineDepthStencilStateCreateFlags = {},
	stencil_test_enable:      b32                                     = false,
	front:                    vk.StencilOpState                       = {},
	back:                     vk.StencilOpState                       = {},
	depth_bounds_test_enable: b32                                     = false,
	min_depth_bounds:         f32                                     = 0,
	max_depth_bounds:         f32                                     = 1,
) -> (
	depth_stencil_state: vk.PipelineDepthStencilStateCreateInfo
) {
	depth_stencil_state = {
		sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		flags                 = flags,
		depthTestEnable       = depth_test_enable,
		depthWriteEnable      = depth_write_enable,
		depthCompareOp        = depth_compare_op,
		depthBoundsTestEnable = depth_bounds_test_enable,
		stencilTestEnable     = stencil_test_enable,
		front                 = front,
		back                  = back,
		minDepthBounds        = min_depth_bounds,
		maxDepthBounds        = max_depth_bounds,
	}

	return depth_stencil_state
}

// NOTE(Mitchell): Needs to contain viewport and scissor
vk_dynamic_state_create :: proc(
	dynamic_states: []vk.DynamicState = {.VIEWPORT, .SCISSOR}
) -> (
	dynamic_state: vk.PipelineDynamicStateCreateInfo
) {		
	found_viewport: bool
	for state in dynamic_states do if state == .VIEWPORT do found_viewport = true
	assert(found_viewport)
	
	found_scissor:  bool
	for state in dynamic_states do if state == .SCISSOR do found_scissor = true
	assert(found_scissor)
	
	dynamic_state = {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamic_states)),
		pDynamicStates    = raw_data(dynamic_states)
	}
	
	return dynamic_state
}

vk_swapchain_set_recreation_callback :: proc(
	callback: proc(vk.Extent2D)
) {
	assert(vk_context.initialised)
	assert(vk_context.swapchain.initialised)
	
	vk_context.swapchain.on_recreation = callback
}

vk_image_find_supported_format :: proc(
	candidates: []vk.Format,
	tiling:     vk.ImageTiling,
	features:   vk.FormatFeatureFlags
) -> (
	supported_format: Maybe(vk.Format)
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	
	for format in candidates {
		format_properties: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(vk_context.device.physical, format, &format_properties)

		#partial switch (tiling) {
		case .LINEAR: if (features & format_properties.linearTilingFeatures) == features do return format
		case .OPTIMAL: if (features & format_properties.optimalTilingFeatures) == features do return format
		case: assert(false)
		}
	}

	return nil
}

vk_image_format_has_stencil_component :: proc(
	format: vk.Format
) -> (
	has_stencil: bool
) {
	#partial switch (format) {
	case .D16_UNORM_S8_UINT: return true 
	case .D24_UNORM_S8_UINT: return true
	case .D32_SFLOAT_S8_UINT: return true
	case: return false
	}
}

vk_extent_get_mip_levels :: proc(
	extent: vk.Extent2D
) -> (
	mip_levels: u32
) {
	return u32(math.floor(math.log2(f32(max(extent.width, extent.height))))) + 1
}

vk_image_create :: proc(
	format:       vk.Format,
	tiling:       vk.ImageTiling,
	extent:       vk.Extent3D,
	usage:        vk.ImageUsageFlags,
	aspect_mask:  vk.ImageAspectFlags,
	vk_allocator: ^VK_Allocator,
	mip_levels:   u32                 = 1,
	samples:      vk.SampleCountFlags = {._1},
	image_type:   vk.ImageType        = .D2,
	view_type:    vk.ImageViewType    = .D2,
	sharing_mode: vk.SharingMode      = .EXCLUSIVE,
	queues:       VK_Queue_Types      = {},
	flags:        vk.ImageCreateFlags = {},
	array_layers: u32                 = 1,
) -> (
	image: VK_Image
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(vk_allocator != nil)
	
	image.format       = format
	image.extent       = extent
	image.vk_allocator = vk_allocator
	
	queue_indices: [len(VK_Queue_Type)]u32
	for &index in queue_indices do index = max(u32)
	
	i: u32
	for queue in queues {
		stored: bool
		for index in queue_indices do if index == vk_context.device.queue_indices[queue] do stored = true
		
		if !stored {
			queue_indices[i] = vk_context.device.queue_indices[queue]
			i += 1
		}
	}
	
	image_create_info: vk.ImageCreateInfo = {
		sType                 = .IMAGE_CREATE_INFO,
		flags                 = flags,
		imageType             = image_type,
		format                = format,
		extent                = extent,
		mipLevels             = mip_levels,
		arrayLayers           = array_layers,
		samples               = samples,
		tiling                = tiling,
		usage                 = usage,
		sharingMode           = sharing_mode,
		queueFamilyIndexCount = u32(i),
		pQueueFamilyIndices   = raw_data(queue_indices[:]),
	}
	vk_warn(vk.CreateImage(vk_context.device.logical, &image_create_info, nil, &image.handle))
	
	memory_requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(vk_context.device.logical, image.handle, &memory_requirements)

	memory_type_index := vk_memory_type_find_index(vk_context.device.physical, {.DEVICE_LOCAL}, memory_requirements.memoryTypeBits)
	assert(memory_type_index != nil)

	memory_info: vk.MemoryAllocateInfo = {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = memory_requirements.size,
		memoryTypeIndex = memory_type_index.(u32)
	}

	allocate_info: VK_Allocate_Info = {
		memory_info     = memory_info,
		memory_map_type = .Never
	}
 
	image.allocation = vk_allocator->allocate(&allocate_info)

	vk.BindImageMemory(vk_context.device.logical, image.handle, image.allocation.handle, image.allocation.offset)

	image.subresource_range = {
		aspectMask     = aspect_mask,
		baseMipLevel   = 0,
		levelCount     = mip_levels,
		baseArrayLayer = 0,
		layerCount     = array_layers,
	}

	image_view_create_info: vk.ImageViewCreateInfo = {
		sType    = .IMAGE_VIEW_CREATE_INFO,
		image    = image.handle,
		viewType = view_type,
		format   = format,
		components = {
			r = .IDENTITY,
			g = .IDENTITY,
			b = .IDENTITY,
			a = .IDENTITY,
		},
		subresourceRange = image.subresource_range
	}
	vk_warn(vk.CreateImageView(vk_context.device.logical, &image_view_create_info, nil, &image.view))
	
	return image
}

vk_image_destroy :: proc(
	image: ^VK_Image
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(image != nil)
	assert(image.vk_allocator != nil)

	vk.DestroyImageView(vk_context.device.logical, image.view, nil)
	vk.DestroyImage(vk_context.device.logical, image.handle, nil)
	image.vk_allocator->deallocate(&image.allocation)
}

vk_image_generate_mip_maps :: proc(
	command_pool: VK_Command_Pool,
	image:        ^VK_Image,
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	
	format_properties: vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(vk_context.device.physical, image.format, &format_properties)
	assert(.SAMPLED_IMAGE_FILTER_LINEAR in format_properties.optimalTilingFeatures)
	
	barrier: vk.ImageMemoryBarrier = {
		sType = .IMAGE_MEMORY_BARRIER,
		image = image.handle,
		subresourceRange = {
			aspectMask     = {.COLOR},
			baseArrayLayer = 0,
			layerCount     = 1,
			levelCount     = 1
		}
	}
	
	transition := vk_command_buffer_begin_single(command_pool)

	mip_levels := image.subresource_range.levelCount
	mip_width:  i32 = i32(image.extent.width)
	mip_height: i32 = i32(image.extent.height)

	for i in 1..<mip_levels {
		barrier.subresourceRange.baseMipLevel = i - 1
		barrier.oldLayout = .TRANSFER_DST_OPTIMAL
		barrier.newLayout = .TRANSFER_SRC_OPTIMAL
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.TRANSFER_READ}

		vk.CmdPipelineBarrier(
			transition.handle,
			{.TRANSFER},
			{.TRANSFER},
			{},
			0, nil,
			0, nil,
			1, &barrier
		)

		blit: vk.ImageBlit = {
			srcOffsets = {
				{0, 0, 0},
				{
					x = mip_width,
					y = mip_height,
					z = 1
				}
			},
			srcSubresource = {
				aspectMask     = {.COLOR},
				mipLevel       = i - 1,
				baseArrayLayer = 0,
				layerCount     = 1
			},
			dstOffsets = {
				{0, 0, 0},
				{
					x = mip_width / 2 if mip_width > 1 else 1,
					y = mip_height / 2 if mip_height > 1 else 1,
					z = 1
				}
			},
			dstSubresource = {
				aspectMask     = {.COLOR},
				mipLevel       = i,
				baseArrayLayer = 0,
				layerCount     = 1
			}
		}

		vk.CmdBlitImage(
			transition.handle,
			image.handle, .TRANSFER_SRC_OPTIMAL,
			image.handle, .TRANSFER_DST_OPTIMAL,
			1, &blit,
			.LINEAR
		)

		barrier.oldLayout = .TRANSFER_SRC_OPTIMAL
		barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
		barrier.srcAccessMask = {.TRANSFER_READ}
		barrier.dstAccessMask = {.SHADER_READ}

		vk.CmdPipelineBarrier(
			transition.handle,
			{.TRANSFER},
			{.FRAGMENT_SHADER},
			{},
			0, nil,
			0, nil,
			1, &barrier
		)

		if mip_width > 1 do mip_width /= 2
		if mip_height > 1 do mip_height /= 2
	}

	barrier.subresourceRange.baseMipLevel = mip_levels - 1
	barrier.oldLayout = .TRANSFER_DST_OPTIMAL
	barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
	barrier.srcAccessMask = {.TRANSFER_WRITE}
	barrier.dstAccessMask = {.SHADER_READ}

	vk.CmdPipelineBarrier(
		transition.handle,
		{.TRANSFER},
		{.FRAGMENT_SHADER},
		{},
		0, nil,
		0, nil,
		1, &barrier
	)

	vk_command_buffer_end_single(transition)
}

vk_depth_image_create :: proc(
	format:       vk.Format,
	tiling:       vk.ImageTiling,
	extent:       vk.Extent3D,
	usage:        vk.ImageUsageFlags,
	vk_allocator: ^VK_Allocator,
	aspect_mask:  vk.ImageAspectFlags  = {.DEPTH},
	samples:      vk.SampleCountFlags = {._1},
	image_type:   vk.ImageType        = .D2,
	view_type:    vk.ImageViewType    = .D2,
	sharing_mode: vk.SharingMode      = .EXCLUSIVE,
	queues:       VK_Queue_Types      = {},
	flags:        vk.ImageCreateFlags = {},
	mip_levels:   u32                 = 1,
	array_layers: u32                 = 1,
) -> (
	depth_image: VK_Image
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(vk_allocator != nil)
	assert(.DEPTH in aspect_mask)
	
	return vk_image_create(
		format,
		tiling,
		extent,
		usage,
		aspect_mask,
		vk_allocator,
		mip_levels,
		samples,
		image_type,
		view_type,
		sharing_mode,
		queues,
		flags,
		array_layers
	)
}

vk_texture_image_create :: proc(
	tiling:       vk.ImageTiling,
	extent:       vk.Extent3D,
	format:       vk.Format,
	vk_allocator: ^VK_Allocator,
	mip_levels:   u32                 = 1,
	usage:        vk.ImageUsageFlags  = {.TRANSFER_DST, .SAMPLED},
	aspect_mask:  vk.ImageAspectFlags = {.COLOR},
	samples:      vk.SampleCountFlags = {._1},
	image_type:   vk.ImageType        = .D2,
	view_type:    vk.ImageViewType    = .D2,
	sharing_mode: vk.SharingMode      = .EXCLUSIVE,
	queues:       VK_Queue_Types      = {},
	flags:        vk.ImageCreateFlags = {},
	array_layers: u32                 = 1,
) -> (
	depth_image: VK_Image
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(vk_allocator != nil)
	assert(.COLOR in aspect_mask)
	assert(.TRANSFER_DST in usage)
	assert(.SAMPLED in usage)

	usage := usage
	if mip_levels > 1 do usage += {.TRANSFER_SRC}
	
	return vk_image_create(
		format,
		tiling,
		extent,
		usage,
		aspect_mask,
		vk_allocator,
		mip_levels,
		samples,
		image_type,
		view_type,
		sharing_mode,
		queues,
		flags,
		array_layers
	)
}

vk_sampler_create :: proc(
	mipmap_mode:              vk.SamplerMipmapMode  = .LINEAR,
	mip_lod_bias:             f32                   = 0,
	min_lod:                  f32                   = 0,
	max_lod:                  f32                   = 0,
	mag_filter:               vk.Filter             = .LINEAR,
	min_filter:               vk.Filter             = .LINEAR,
	address_mode_u:           vk.SamplerAddressMode = .REPEAT,
	address_mode_v:           vk.SamplerAddressMode = .REPEAT,
	address_mode_w:           vk.SamplerAddressMode = .REPEAT,
	anisotropy_enable:        b32                   = false,
	max_anisotropy:           f32                   = 0,
	border_color:             vk.BorderColor        = .INT_OPAQUE_BLACK,
	unnormalized_coordinates: b32                   = false,
	compare_enable:           b32                   = false,
	compare_op:               vk.CompareOp          = .ALWAYS,
	flags:                    vk.SamplerCreateFlags = {},
) -> (
	sampler: vk.Sampler
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	
	sampler_create_info: vk.SamplerCreateInfo = {
		sType                   = .SAMPLER_CREATE_INFO,
		flags                   = flags,
		magFilter               = mag_filter,
		minFilter               = min_filter,
		mipmapMode              = mipmap_mode,
		addressModeU            = address_mode_u,
		addressModeV            = address_mode_v,
		addressModeW            = address_mode_w,
		mipLodBias              = mip_lod_bias,
		anisotropyEnable        = anisotropy_enable,
		maxAnisotropy           = max_anisotropy,
		compareEnable           = compare_enable,
		compareOp               = compare_op,
		minLod                  = min_lod,
		maxLod                  = max_lod,
		borderColor             = border_color,
		unnormalizedCoordinates = unnormalized_coordinates,
	}
	vk_warn(vk.CreateSampler(vk_context.device.logical, &sampler_create_info, nil, &sampler))

	return sampler
}

vk_sampler_destroy :: proc(
	sampler: vk.Sampler
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	
	vk.DestroySampler(vk_context.device.logical, sampler, nil)
}

vk_rendering_info_create :: proc(
	color_attachment_formats:  []vk.Format = {},
	depth_attachment_format:   vk.Format   = vk.Format.UNDEFINED,
	stencil_attachment_format: vk.Format   = vk.Format.UNDEFINED,
	view_mask:                 u32         = 0,
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

vk_graphics_pipeline_create :: proc (
	rendering_info:       ^vk.PipelineRenderingCreateInfo,
	vertex_input_state:   ^vk.PipelineVertexInputStateCreateInfo   = nil,
	input_assembly_state: ^vk.PipelineInputAssemblyStateCreateInfo = nil,
	viewport_state:       ^vk.PipelineViewportStateCreateInfo      = nil,
	rasterizer_state:     ^vk.PipelineRasterizationStateCreateInfo = nil,
	multisample_state:    ^vk.PipelineMultisampleStateCreateInfo   = nil,
	depth_stencil_state:  ^vk.PipelineDepthStencilStateCreateInfo  = nil,
	color_blend_state:    ^vk.PipelineColorBlendStateCreateInfo    = nil,
	dynamic_state:        ^vk.PipelineDynamicStateCreateInfo       = nil,
	shader_stages:        []vk.PipelineShaderStageCreateInfo       = {},
	descriptor_layouts:   []vk.DescriptorSetLayout                 = {},
	push_constant_ranges: []vk.PushConstantRange                   = {}
) -> (
	pipeline: vk.Pipeline,
	pipeline_layout: vk.PipelineLayout
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(rendering_info != nil)
	
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
		pDepthStencilState  = depth_stencil_state,
		pColorBlendState    = color_blend_state,
		pDynamicState       = dynamic_state,
	}
	vk_warn(vk.CreateGraphicsPipelines(vk_context.device.logical, 0, 1, &pipeline_create_info, nil, &pipeline))

	return pipeline, pipeline_layout
}

vk_graphics_pipeline_destroy :: proc(
	pipeline:        vk.Pipeline,
	pipeline_layout: vk.PipelineLayout
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	
	vk_warn(vk.DeviceWaitIdle(vk_context.device.logical))
	vk.DestroyPipelineLayout(vk_context.device.logical, pipeline_layout, nil)
	vk.DestroyPipeline(vk_context.device.logical, pipeline, nil)
}

vk_command_graphics_pipeline_bind :: #force_inline proc(
	command_buffer: VK_Command_Buffer,
	pipeline:       vk.Pipeline
) {
	vk.CmdBindPipeline(command_buffer.handle, .GRAPHICS, pipeline)
}

vk_command_pool_create :: proc(
	queue_type: VK_Queue_Type
) -> (
	command_pool: VK_Command_Pool
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	command_pool.queue_type = queue_type

	command_pool_create_info: vk.CommandPoolCreateInfo = {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = vk_context.device.queue_indices[queue_type]
	}
	
	vk_warn(vk.CreateCommandPool(vk_context.device.logical, &command_pool_create_info, nil, &command_pool.handle))

	return command_pool
}

vk_command_pool_destroy :: proc(
	command_pool: VK_Command_Pool
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	vk.DestroyCommandPool(vk_context.device.logical, command_pool.handle, nil)
}

vk_command_buffer_create :: proc {
	vk_command_buffer_create_single,
	vk_command_buffer_create_slice,
}

vk_command_buffer_create_single :: proc(
	command_pool: VK_Command_Pool,
	level:        vk.CommandBufferLevel = .PRIMARY
) -> (
	command_buffer: VK_Command_Buffer
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(command_pool.handle != 0)

	command_buffer.command_pool = command_pool
	
	allocate_info: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool.handle,
		commandBufferCount = 1,
		level              = level
	}
	vk_warn(vk.AllocateCommandBuffers(vk_context.device.logical, &allocate_info, &command_buffer.handle))

	return command_buffer
}

vk_command_buffer_create_slice :: proc(
	command_pool: VK_Command_Pool,
	level:        vk.CommandBufferLevel = .PRIMARY,
	count:        u32,
	allocator := context.allocator
) -> (
	command_buffers: []VK_Command_Buffer
) {
	context.allocator = allocator
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(command_pool.handle != 0)

	allocate_info: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool.handle,
		commandBufferCount = 1,
		level              = level
	}
	command_buffers = make([]VK_Command_Buffer, count)
	for &command_buffer in command_buffers {
		command_buffer.command_pool = command_pool
		vk_warn(vk.AllocateCommandBuffers(vk_context.device.logical, &allocate_info, &command_buffer.handle))
	}

	return command_buffers
}

vk_command_buffer_destroy :: proc {
	vk_command_buffer_destroy_single,
	vk_command_buffer_destroy_slice,
}

vk_command_buffer_destroy_single :: proc(
	command_buffer: VK_Command_Buffer
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	command_buffer := command_buffer
	
	vk.FreeCommandBuffers(vk_context.device.logical, command_buffer.command_pool.handle, 1, &command_buffer.handle)
}

vk_command_buffer_destroy_slice :: proc(
	command_buffers: []VK_Command_Buffer
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	
	for &command_buffer in command_buffers do vk.FreeCommandBuffers(vk_context.device.logical, command_buffer.command_pool.handle, 1, &command_buffer.handle)
	delete(command_buffers)
}

vk_command_buffer_reset :: proc(
	command_buffer: VK_Command_Buffer
) {
	vk_warn(vk.ResetCommandBuffer(command_buffer.handle, {.RELEASE_RESOURCES}))
}

vk_command_buffer_begin :: proc(
	command_buffer: VK_Command_Buffer,
	flags:          vk.CommandBufferUsageFlags = {.ONE_TIME_SUBMIT}
) {
	begin_info: vk.CommandBufferBeginInfo = {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = flags
	}
	vk_warn(vk.BeginCommandBuffer(command_buffer.handle, &begin_info))
}

vk_command_buffer_end :: proc(
	command_buffer: VK_Command_Buffer
) {
	vk_warn(vk.EndCommandBuffer(command_buffer.handle))
}

vk_command_buffer_begin_single :: proc(
	command_pool: VK_Command_Pool
) -> (
	command_buffer: VK_Command_Buffer
) {
	command_buffer = vk_command_buffer_create(command_pool)
	vk_command_buffer_begin(command_buffer, {.ONE_TIME_SUBMIT})

	return command_buffer
}

vk_command_buffer_end_single :: proc(
	command_buffer: VK_Command_Buffer
) {
	vk_command_buffer_end(command_buffer)
	vk_queue_submit(command_buffer)
	vk_command_buffer_destroy(command_buffer)
}

vk_semaphore_create :: proc {
	vk_semaphore_create_single,
	vk_semaphore_create_slice,
}

vk_semaphore_create_single :: proc() -> (
	semaphore: vk.Semaphore 
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	semaphore_create_info: vk.SemaphoreCreateInfo = { sType = .SEMAPHORE_CREATE_INFO }
	vk_warn(vk.CreateSemaphore(vk_context.device.logical, &semaphore_create_info, nil, &semaphore))

	return semaphore
}

vk_semaphore_create_slice :: proc(
	count: u32,
	allocator := context.allocator
) -> (
	semaphores: []vk.Semaphore
) {
	context.allocator = allocator
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	semaphore_create_info: vk.SemaphoreCreateInfo = { sType = .SEMAPHORE_CREATE_INFO }
	semaphores = make([]vk.Semaphore, count)
	for i in 0..<count do vk_warn(vk.CreateSemaphore(vk_context.device.logical, &semaphore_create_info, nil, &semaphores[i]))

	return semaphores
}

vk_semaphore_destroy :: proc{
	vk_semaphore_destroy_single,
	vk_semaphore_destroy_slice,
}

vk_semaphore_destroy_single :: proc(
	semaphore: vk.Semaphore
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	
	vk_warn(vk.DeviceWaitIdle(vk_context.device.logical))
	vk.DestroySemaphore(vk_context.device.logical, semaphore, nil)
}

vk_semaphore_destroy_slice :: proc(
	semaphores: []vk.Semaphore
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	vk_warn(vk.DeviceWaitIdle(vk_context.device.logical))
	for semaphore in semaphores do vk.DestroySemaphore(vk_context.device.logical, semaphore, nil)
	delete(semaphores)
}

vk_fence_create :: proc {
	vk_fence_create_single,
	vk_fence_create_slice,
}

vk_fence_create_single :: proc(
	signaled: bool = true
) -> (
	fence: vk.Fence
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	fence_create_info: vk.FenceCreateInfo = {
		sType = .FENCE_CREATE_INFO,
		flags = {}
	}
	if signaled do fence_create_info.flags = {.SIGNALED}
	
	vk_warn(vk.CreateFence(vk_context.device.logical, &fence_create_info, nil, &fence))

	return fence
}

vk_fence_create_slice :: proc(
	signaled: bool = true,
	count:    u32,
	allocator := context.allocator
) -> (
	fences: []vk.Fence
) {
	context.allocator = allocator
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	fence_create_info: vk.FenceCreateInfo = {
		sType = .FENCE_CREATE_INFO,
		flags = {}
	}
	if signaled do fence_create_info.flags = {.SIGNALED}

	fences = make([]vk.Fence, count)
	for i in 0..<count do vk_warn(vk.CreateFence(vk_context.device.logical, &fence_create_info, nil, &fences[i]))

	return fences
}

vk_fence_destroy :: proc{
	vk_fence_destroy_single,
	vk_fence_destroy_slice,
}

vk_fence_destroy_single :: proc(
	fence: vk.Fence
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	
	vk_warn(vk.DeviceWaitIdle(vk_context.device.logical))
	vk.DestroyFence(vk_context.device.logical, fence, nil)
}

vk_fence_destroy_slice :: proc(
	fences: []vk.Fence
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	vk_warn(vk.DeviceWaitIdle(vk_context.device.logical))
	for fence in fences do vk.DestroyFence(vk_context.device.logical, fence, nil)
	delete(fences)
}

vk_swapchain_get_next_image_index :: proc(
	signal_image_available: vk.Semaphore,
	block_until:            vk.Fence,
	allocator := context.allocator
) -> (
	image_index: u32
) {
	context.allocator = allocator
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(vk_context.swapchain.initialised)

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
		log.info("Vulkan - Swapchain: recreating swapchain")
		vk_swapchain_recreate()
		return image_index
	case:
		log.fatal("Vulkan - Swapchain: Failed to acquire next swapchain image, exiting...")
		os.exit(-1)
	}
}

vk_queue_submit :: proc(
	command_buffer:  VK_Command_Buffer,
	signal_finished: vk.Semaphore          = 0,
	wait_for:        vk.Semaphore          = 0,
	wait_for_stages: vk.PipelineStageFlags = {},
	block_until:     vk.Fence              = 0,
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	command_buffer := command_buffer

	submit_info: vk.SubmitInfo = {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &command_buffer.handle
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
		vk_warn(vk.QueueSubmit(vk_context.device.queues[command_buffer.command_pool.queue_type], 1, &submit_info, block_until))
		vk_warn(vk.WaitForFences(vk_context.device.logical, 1, &block_until, true, max(u64)))
	} else {
		vk_warn(vk.QueueSubmit(vk_context.device.queues[command_buffer.command_pool.queue_type], 1, &submit_info, 0))
		vk_warn(vk.QueueWaitIdle(vk_context.device.queues[command_buffer.command_pool.queue_type]))
	}
}

vk_present :: proc(
	wait_render_finished: vk.Semaphore,
	image_index:          u32,
	allocator := context.allocator
) {
	context.allocator = allocator
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(vk_context.swapchain.initialised)

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
		log.info("Vulkan - Swapchain: recreating swapchain")
		vk_swapchain_recreate()
	case:
		log.fatal("Vulkan - Queue: Failed to present to queue, exiting...")
		os.exit(-1)
	}
}

vk_command_viewport_set :: proc(
	command_buffer: VK_Command_Buffer,
	viewports:      []vk.Viewport
) {
	vk.CmdSetViewport(command_buffer.handle, 0, u32(len(viewports)), raw_data(viewports))
}

vk_command_scissor_set :: proc(
	command_buffer: VK_Command_Buffer,
	scissors:       []vk.Rect2D
) {
	vk.CmdSetScissor(command_buffer.handle, 0, u32(len(scissors)), raw_data(scissors))
}

vk_swapchain_get_image :: proc(
	index: u32
) -> (
	image: ^VK_Image
) {
	assert(vk_context.initialised)
	assert(vk_context.swapchain.initialised)
	assert(index < u32(len(vk_context.swapchain.images)))

	return &vk_context.swapchain.images[index]
}

vk_swapchain_get_image_handle :: proc(
	index: u32
) -> (
	handle: vk.Image
) {
	assert(vk_context.initialised)
	assert(vk_context.swapchain.initialised)
	assert(index < u32(len(vk_context.swapchain.images)))

	return vk_context.swapchain.images[index].handle
}

vk_swapchain_get_image_view :: proc(
	index: u32
) -> (
	view: vk.ImageView
) {
	assert(vk_context.initialised)
	assert(vk_context.swapchain.initialised)
	assert(index < u32(len(vk_context.swapchain.images)))

	return vk_context.swapchain.images[index].view
}

vk_swapchain_get_image_format :: proc() -> (
	format: vk.Format
) {
	assert(vk_context.initialised)
	assert(vk_context.swapchain.initialised)

	return vk_context.swapchain.images[0].format
}

vk_swapchain_get_image_count :: proc() -> (
	image_count: u32
) {
	assert(vk_context.initialised)
	assert(vk_context.swapchain.initialised)

	return u32(len(vk_context.swapchain.images))
}

vk_swapchain_get_extent :: proc() -> (
	extent: vk.Extent2D
) {
	assert(vk_context.initialised)
	assert(vk_context.swapchain.initialised)

	return vk_context.swapchain.attributes.extent
}

vk_command_image_barrier :: proc(
	command_buffer:    VK_Command_Buffer,
	image:             ^VK_Image,
	src_access_mask:   vk.AccessFlags           = {},
	dst_access_mask:   vk.AccessFlags           = {},
	old_layout:        vk.ImageLayout           = .UNDEFINED,
	new_layout:        vk.ImageLayout           = .UNDEFINED,
	subresource_range: vk.ImageSubresourceRange = {{.COLOR}, 0, 1, 0, 1},
	src_stage_mask:    vk.PipelineStageFlags    = {},
	dst_stage_mask:    vk.PipelineStageFlags    = {}
) {
	assert(vk_context.initialised)
	assert(image != nil)

	barrier: vk.ImageMemoryBarrier = {
		sType            = .IMAGE_MEMORY_BARRIER,
		dstAccessMask    = dst_access_mask,
		srcAccessMask    = src_access_mask,
		oldLayout        = old_layout,
		newLayout        = new_layout,
		image            = image.handle,
		subresourceRange = subresource_range
	}

	vk.CmdPipelineBarrier(
		command_buffer.handle,
		src_stage_mask,
		dst_stage_mask,
		{},
		0, nil,
		0, nil,
		1, &barrier
	)
}

vk_command_draw :: #force_inline proc(
	command_buffer: VK_Command_Buffer,
	vertex_count:   u32,
	instance_count: u32 = 1,
	first_vertex:   u32 = 0,
	first_instance: u32 = 0
) {
	vk.CmdDraw(command_buffer.handle, vertex_count, instance_count, first_vertex, first_instance)
}

vk_command_draw_indexed :: #force_inline proc(
	command_buffer: VK_Command_Buffer,
	index_count:    u32,
	instance_count: u32 = 1,
	first_index:    u32 = 0,
	vertex_offset:  i32 = 0,
	first_instance: u32 = 0
) {
	vk.CmdDrawIndexed(command_buffer.handle, index_count, instance_count, first_index, vertex_offset, first_instance)
}

vk_command_end_rendering :: #force_inline proc(
	command_buffer: VK_Command_Buffer
) {
	vk.CmdEndRendering(command_buffer.handle)
}

vk_color_attachment_create :: proc(
	image_view:           vk.ImageView,
	load_op:              vk.AttachmentLoadOp  = .CLEAR,
	store_op:             vk.AttachmentStoreOp = .STORE,
	clear_color:          [4]f32               = {0, 0, 0, 0},
	resolve_mode:         vk.ResolveModeFlags  = {},
	resolve_image_view:   vk.ImageView         = 0,
	resolve_image_layout: vk.ImageLayout       = .UNDEFINED,
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

vk_depth_attachment_create :: proc(
	image_view:           vk.ImageView,
	image_layout:         vk.ImageLayout            = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	load_op:              vk.AttachmentLoadOp       = .CLEAR,
	store_op:             vk.AttachmentStoreOp      = .STORE,
	depth_stencil_value:  vk.ClearDepthStencilValue = {1, 0},
	resolve_mode:         vk.ResolveModeFlags       = {},
	resolve_image_view:   vk.ImageView              = 0,
	resolve_image_layout: vk.ImageLayout            = .UNDEFINED,
) -> (
	depth_attachment: vk.RenderingAttachmentInfo
) {
	clear_value: vk.ClearValue
	clear_value.depthStencil = depth_stencil_value
	
	depth_attachment = {
		sType              = .RENDERING_ATTACHMENT_INFO,
		imageView          = image_view,
		imageLayout        = image_layout,
		resolveMode        = resolve_mode,
		resolveImageView   = resolve_image_view,
		resolveImageLayout = resolve_image_layout,
		loadOp             = load_op,
		storeOp            = store_op,
		clearValue         = clear_value,
	}

	return depth_attachment
}

vk_command_begin_rendering :: proc(
	command_buffer:     VK_Command_Buffer,
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

	vk.CmdBeginRendering(command_buffer.handle, &rendering_info)
}

// NOTE(Mitchell): We don't support sparse binding so locations must be contiguous
vk_vertex_description_create :: proc(
	$Vertex:          typeid,
	binding:          u32    = 0,
	start_location:   u32    = 0,
	allocator := context.allocator
) -> (
	binding_description:    vk.VertexInputBindingDescription,
	attribute_descriptions: []vk.VertexInputAttributeDescription
) {
	context.allocator = allocator

	binding_description = {
		binding   = binding,
		stride    = u32(type_info_of(Vertex).size),
		inputRate = .VERTEX
	}
	
	field_count := reflect.struct_field_count(Vertex)
	attribute_descriptions = make([]vk.VertexInputAttributeDescription, field_count)
	
	for i in 0..<field_count {
		field := reflect.struct_field_at(Vertex, i)
		
		attribute_descriptions[i] = {
			location = start_location + u32(i),
			binding  = binding,
			offset   = u32(field.offset),
		}

		if field.type.size == 4 {
			attribute_descriptions[i].format = .R32_SFLOAT
		} else if field.type.size == 8 {
			attribute_descriptions[i].format = .R32G32_SFLOAT
		} else if field.type.size == 12 {
			attribute_descriptions[i].format = .R32G32B32_SFLOAT
		} else if field.type.size == 16 {
			attribute_descriptions[i].format = .R32G32B32A32_SFLOAT
		} else {
			assert(false)
		}
	}

	return binding_description, attribute_descriptions
}

vk_buffer_create :: proc(
	size:            vk.DeviceSize,
	usage:           vk.BufferUsageFlags,
	memory_map_type: VK_Memory_Map_Type,
	vk_allocator:    ^VK_Allocator,
	property_flags:  vk.MemoryPropertyFlags      = {},
	memory_flags:    vk.MemoryAllocateFlags      = {},
	sharing_mode:    vk.SharingMode              = .EXCLUSIVE,
	queues:          VK_Queue_Types              = {},
	flags:           vk.BufferCreateFlags        = {}
) -> (
	buffer: VK_Buffer
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)

	buffer.size = size

	queue_indices: [len(VK_Queue_Type)]u32
	for &index in queue_indices do index = max(u32)
	
	i: u32
	for queue in queues {
		stored: bool
		for index in queue_indices do if index == vk_context.device.queue_indices[queue] do stored = true 
		
		if !stored {
			queue_indices[i] = vk_context.device.queue_indices[queue]
			i += 1
		}
	}
	
	buffer_create_info: vk.BufferCreateInfo = {
		sType                 = .BUFFER_CREATE_INFO,
		size                  = size,
		usage                 = usage,
		sharingMode           = sharing_mode,
		queueFamilyIndexCount = i,
		pQueueFamilyIndices   = raw_data(queue_indices[:]),
		flags                 = flags
	}
	vk_warn(vk.CreateBuffer(vk_context.device.logical, &buffer_create_info, nil, &buffer.handle))
	
	allocate_info: VK_Allocate_Info = {
		memory_flags    = memory_flags,
		memory_map_type = memory_map_type
	}
	
	memory_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(vk_context.device.logical, buffer.handle, &memory_requirements)
	
	allocate_info.memory_info = {
		sType          = .MEMORY_ALLOCATE_INFO,
		allocationSize = size if size >= memory_requirements.size else memory_requirements.size,
		pNext          = &vk.MemoryAllocateFlagsInfo {
			sType = .MEMORY_ALLOCATE_FLAGS_INFO,
			flags = memory_flags
		}
	}

	type_index := vk_memory_type_find_index(vk_context.device.physical, property_flags, memory_requirements.memoryTypeBits)
	assert(type_index != nil)

	allocate_info.memory_info.memoryTypeIndex = type_index.(u32)
	buffer.vk_allocator = vk_allocator
	buffer.allocation   = vk_allocator->allocate(&allocate_info)
	vk_warn(vk.BindBufferMemory(vk_context.device.logical, buffer.handle, buffer.allocation.handle, buffer.allocation.offset))

	return buffer
}

vk_buffer_destroy :: proc(
	buffer: ^VK_Buffer
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(buffer != nil)
	
	buffer.vk_allocator->deallocate(&buffer.allocation)
	vk.DestroyBuffer(vk_context.device.logical, buffer.handle, nil)
}

vk_uniform_buffer_create :: proc(
	size:         vk.DeviceSize,
	vk_allocator: ^VK_Allocator,
	memory_flags: vk.MemoryAllocateFlags = {},
	sharing_mode: vk.SharingMode         = .EXCLUSIVE,
	queues:       VK_Queue_Types         = {},
	flags:        vk.BufferCreateFlags   = {}
) -> (
	uniform_buffer: VK_Buffer
) {
	assert(vk_allocator != nil)

	uniform_buffer = vk_buffer_create(
		size,
		{.UNIFORM_BUFFER, .TRANSFER_DST},
		.Always,
		vk_allocator,
		{.HOST_VISIBLE, .HOST_COHERENT},
		memory_flags,
		sharing_mode,
		queues,
		flags
	)

	return uniform_buffer
}

vk_storage_buffer_create :: proc(
	size:         vk.DeviceSize,
	vk_allocator: ^VK_Allocator,
	memory_flags: vk.MemoryAllocateFlags = {},
	sharing_mode: vk.SharingMode         = .EXCLUSIVE,
	queues:       VK_Queue_Types         = {},
	flags:        vk.BufferCreateFlags   = {}
) -> (
	storage_buffer: VK_Buffer
) {
	assert(vk_allocator != nil)

	storage_buffer = vk_buffer_create(
		size,
		{.STORAGE_BUFFER, .TRANSFER_DST},
		.Always,
		vk_allocator,
		{.HOST_VISIBLE, .HOST_COHERENT},
		memory_flags,
		sharing_mode,
		queues,
		flags
	)

	return storage_buffer
}

// NOTE(Mitchell): We may want to have {.DEVICE_LOCAL} be configurable i.e. {.HOST_VISIBLE, .HOST_COHERENT}
vk_vertex_buffer_create :: proc(
	size:         vk.DeviceSize,
	vk_allocator: ^VK_Allocator,
	memory_flags: vk.MemoryAllocateFlags = {},
	sharing_mode: vk.SharingMode         = .EXCLUSIVE,
	queues:       VK_Queue_Types         = {},
	flags:        vk.BufferCreateFlags   = {}
) -> (
	vertex_buffer: VK_Buffer
) {
	vertex_buffer = vk_buffer_create(
		size,
		{.TRANSFER_DST, .VERTEX_BUFFER},
		.Never,
		vk_allocator,
		{.DEVICE_LOCAL},
		memory_flags,
		sharing_mode,
		queues,
		flags
	)
	
	return vertex_buffer
}

vk_command_vertex_buffers_bind :: #force_inline proc(
	command_buffer: VK_Command_Buffer,
	vertex_buffers: []vk.Buffer,
	offsets:        []vk.DeviceSize = {0}
) {
	vk.CmdBindVertexBuffers(command_buffer.handle, 0, u32(len(vertex_buffers)), raw_data(vertex_buffers), raw_data(offsets))
}

vk_index_buffer_create :: proc(
	size:         vk.DeviceSize,
	vk_allocator: ^VK_Allocator,
	memory_flags: vk.MemoryAllocateFlags = {},
	sharing_mode: vk.SharingMode         = .EXCLUSIVE,
	queues:       VK_Queue_Types         = {},
	flags:        vk.BufferCreateFlags   = {}
) -> (
	index_buffer: VK_Buffer
) {
	index_buffer = vk_buffer_create(
		size,
		{.TRANSFER_DST, .INDEX_BUFFER},
		.Never,
		vk_allocator,
		{.DEVICE_LOCAL},
		memory_flags,
		sharing_mode,
		queues,
		flags
	)

	return index_buffer
}

vk_command_index_buffer_bind :: #force_inline proc(
	command_buffer: VK_Command_Buffer,
	index_buffer:   vk.Buffer,
	index_type:     vk.IndexType  = .UINT32,
	offset:         vk.DeviceSize = 0,
) {
	vk.CmdBindIndexBuffer(command_buffer.handle, index_buffer, offset, index_type)
}

vk_buffer_copy :: proc {
	vk_buffer_copy_buffer,
	vk_buffer_copy_staged,
	vk_buffer_copy_mapped,
}

// TODO(Mitchell): Improve abstraction
// NOTE(Mitchell): Command pool must be created with transfer queue support
vk_buffer_copy_buffer :: proc(
	command_pool: VK_Command_Pool,
	src_buffer:   ^VK_Buffer,
	dst_buffer:   ^VK_Buffer,
	size:         vk.DeviceSize
) {
	assert(src_buffer != nil)
	assert(dst_buffer != nil)
	
	copy_region: vk.BufferCopy = {
		size      = size,
		srcOffset = 0,
		dstOffset = 0
	}

	command_buffer := vk_command_buffer_begin_single(command_pool)
	vk.CmdCopyBuffer(command_buffer.handle, src_buffer.handle, dst_buffer.handle, 1, &copy_region)
	vk_command_buffer_end_single(command_buffer)
}

// TODO(Mitchell): Improve abstraction
// NOTE(Mitchell): Command pool must be created with transfer queue support
vk_buffer_copy_staged :: proc(
	command_pool: VK_Command_Pool,
	buffer:       ^VK_Buffer,
	buffer_data:  rawptr,
	vk_allocator: ^VK_Allocator
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(vk_allocator != nil)
	assert(buffer_data != nil)

	staging_buffer := vk_buffer_create(
		buffer.size,
		{.TRANSFER_SRC},
		.Toggle,
		vk_allocator,
		{.HOST_VISIBLE, .HOST_COHERENT},
	)

	data: rawptr
	vk.MapMemory(vk_context.device.logical,
		staging_buffer.allocation.handle,
		staging_buffer.allocation.offset,
		staging_buffer.size,
		{},
		&data
	)
	mem.copy(data, buffer_data, int(buffer.size))
	vk.UnmapMemory(vk_context.device.logical, staging_buffer.allocation.handle)

	vk_buffer_copy_buffer(command_pool, &staging_buffer, buffer, buffer.size)
	vk_buffer_destroy(&staging_buffer)
}

vk_buffer_copy_mapped :: proc(
	buffer:      ^VK_Buffer,
	buffer_data: rawptr,
	flush:       bool = false
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(buffer != nil)
	assert(buffer_data != nil)
	
	mem.copy(buffer.allocation.data, buffer_data, int(buffer.size))

	if flush {
		mapped_memory_range: vk.MappedMemoryRange = {
			sType  = .MAPPED_MEMORY_RANGE,
			memory = buffer.allocation.handle,
			offset = buffer.allocation.offset,
			size   = buffer.size
		}
		vk_warn(vk.FlushMappedMemoryRanges(vk_context.device.logical, 1, &mapped_memory_range))
	}
}

vk_image_copy :: proc {
	vk_image_copy_buffer,
	vk_image_copy_staged,
}

vk_image_copy_buffer :: proc(
	command_pool:       VK_Command_Pool,
	image:              ^VK_Image,
	buffer:             ^VK_Buffer,
	subresource_layers: vk.ImageSubresourceLayers = {{.COLOR}, 0, 0, 1}
) {
	assert(image != nil)
	assert(buffer != nil)

	buffer_image_copy: vk.BufferImageCopy = {
		bufferOffset = buffer.allocation.offset,
		imageSubresource = subresource_layers,
		imageOffset = {0, 0, 0},
		imageExtent = image.extent,
	}

	command_buffer := vk_command_buffer_begin_single(command_pool)
	vk.CmdCopyBufferToImage(command_buffer.handle, buffer.handle, image.handle, .TRANSFER_DST_OPTIMAL, 1, &buffer_image_copy)
	vk_command_buffer_end_single(command_buffer)
}

vk_image_copy_staged :: proc(
	command_pool:       VK_Command_Pool,
	image:              ^VK_Image,
	image_data:         []u8,
	vk_allocator:       ^VK_Allocator,
	subresource_layers: vk.ImageSubresourceLayers = {{.COLOR}, 0, 0, 1}
) {
	assert(vk_context.initialised)
	assert(vk_context.device.initialised)
	assert(image != nil)
	assert(image_data != nil)
	assert(vk_allocator != nil)

	image_size := len(image_data)

	staging_buffer := vk_buffer_create(
		vk.DeviceSize(image_size),
		{.TRANSFER_SRC},
		.Toggle,
		vk_allocator,
		{.HOST_VISIBLE, .HOST_COHERENT},
	)

	data: rawptr
	vk.MapMemory(vk_context.device.logical,
		staging_buffer.allocation.handle,
		staging_buffer.allocation.offset,
		staging_buffer.size,
		{},
		&data
	)
	mem.copy(data, raw_data(image_data), image_size)
	vk.UnmapMemory(vk_context.device.logical, staging_buffer.allocation.handle)

	vk_image_copy_buffer(command_pool, image, &staging_buffer, subresource_layers)
	vk_buffer_destroy(&staging_buffer)
}
