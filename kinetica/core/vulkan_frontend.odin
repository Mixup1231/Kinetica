package core

import vk "vendor:vulkan"

Shader_Stages :: vk.ShaderStageFlags

Shader :: struct {
	shader_module:            vk.ShaderModule,
	shader_stage_create_info: vk.PipelineShaderStageCreateInfo
}

shader_create :: proc(
	filepath: cstring,
	stage:    Shader_Stages,
	name:     cstring,
	allocator := context.allocator
) -> (
	shader: Shader
) {
	ensure(vk_context.initialised)

	device := vk_context.device.logical
	shader = {
		shader_module            = vulkan_create_shader_module(device, filepath),
		shader_stage_create_info = vulkan_get_pipeline_shader_stage_create_info(device, filepath, stage, name)
	}

	return shader
}

shader_destroy :: proc(
	shader: Shader
) {
	ensure(vk_context.initialised)

	vk.DestroyShaderModule(vk_context.device.logical, shader.shader_module, nil)
}
