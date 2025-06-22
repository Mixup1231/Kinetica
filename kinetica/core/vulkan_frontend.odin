package core

import "core:os"
import "core:log"

import vk "vendor:vulkan"

Shader_Module   :: vk.ShaderModule
Descriptor_Set  :: vk.DescriptorSetLayout
Pipeline_Layout :: vk.PipelineLayout 

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
	stages:          []Shader_Stage,
	descriptor_sets: []Descriptor_Set,
	pipeline_layout: Pipeline_Layout,
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
	ensure(vk.ShaderModule(shader_stage.module) != 0)

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
