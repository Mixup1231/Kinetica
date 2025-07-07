package engine

import "../../../kinetica/core"

import vk "vendor:vulkan"

Mesh  :: distinct u32

Texture_Types :: distinct bit_set[Texture_Type]
Texture_Type :: enum {
	Albedo,
	Emissive,
}

Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
	uv:       [2]f32,
}

Texture :: struct {
	image:   core.VK_Image,
	sampler: vk.Sampler,
}

Mesh_Cold :: struct {
	vertices: [dynamic]Vertex,
	indices:  [dynamic]u32,
}

Mesh_Hot :: struct {
	vertex_buffer: core.VK_Buffer,
	index_buffer:  core.VK_Buffer,
	texture_types: Texture_Types
}
