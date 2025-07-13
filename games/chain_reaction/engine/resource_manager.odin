package engine

import "core:os"
import "core:mem"
import "core:log"

import "../../../kinetica/core"
import "../../../kinetica/extensions/obj"

import vk "vendor:vulkan"
import "vendor:stb/image"

Resource_Manager :: struct {
	graphics_pool: core.VK_Command_Pool,
	transfer_pool: core.VK_Command_Pool,
	texture_cache: map[string]Texture,
	textures:      [Texture_Type]Sparse_Array(Mesh, string, Max_Textures_Per_Type),
	mesh_colds:    Sparse_Array(Mesh, Mesh_Cold, Max_Meshes),
	mesh_hots:     Sparse_Array(Mesh, Mesh_Hot, Max_Meshes),
	free_meshes:   [dynamic]Mesh,
	rm_allocator:  mem.Allocator,
	vk_allocator:  core.VK_Allocator,

	initialised: bool,
}

@(private="file")
resource_manager: Resource_Manager

resource_manager_init :: proc(
	allocator := context.allocator
) {
	using resource_manager
	ensure(!initialised)
	context.allocator = allocator
	
	rm_allocator = allocator
	vk_allocator = core.vk_allocator_get_default()

	transfer_pool = core.vk_command_pool_create(.Transfer)
	graphics_pool = core.vk_command_pool_create(.Graphics)

	texture_cache = make(map[string]Texture)
	for &texture_array in textures {
		texture_array = sparse_array_create(Mesh, string, Max_Textures_Per_Type)
	}
	
	mesh_colds = sparse_array_create(Mesh, Mesh_Cold, Max_Meshes)
	mesh_hots  = sparse_array_create(Mesh, Mesh_Hot, Max_Meshes)
	
	free_meshes = make([dynamic]Mesh)
	for i: Mesh = Max_Meshes; i > 0; i -= 1 {
		append(&free_meshes, i)
	} 

	initialised = true
}

resource_manager_destory :: proc() {
	using resource_manager
	ensure(initialised)

	for _, &texture in texture_cache {
		core.vk_image_destroy(&texture.image)
		core.vk_sampler_destroy(texture.sampler)
	}
	
	mesh_cold_slice := sparse_array_slice(&mesh_colds)
	for &mesh_cold in mesh_cold_slice {
		delete(mesh_cold.vertices)
		delete(mesh_cold.indices)
	}
	sparse_array_destroy(&mesh_colds)

	mesh_hot_slice := sparse_array_slice(&mesh_hots)
	for &mesh_hot in mesh_hot_slice {
		core.vk_buffer_destroy(&mesh_hot.vertex_buffer)
		core.vk_buffer_destroy(&mesh_hot.index_buffer)
	}
	sparse_array_destroy(&mesh_hots)

	delete(free_meshes)

	initialised = false
}

resource_manager_load_mesh :: proc(
	obj_filepath:      string,
	texture_filepaths: [Texture_Type]string,
	allocator := context.allocator
) -> (
	mesh: Mesh
) {
	using resource_manager
	ensure(initialised)
	ensure(len(free_meshes) > 0)
	context.allocator = allocator

	mesh = free_meshes[len(free_meshes)-1]
	unordered_remove(&free_meshes, len(free_meshes)-1)
	
	obj_file, read_file := obj.read_file(obj_filepath)
	ensure(read_file)

	obj_mesh := obj.get_mesh(&obj_file)
	defer obj.destory_mesh(&obj_mesh)
	
	mesh_cold := sparse_array_insert(&mesh_colds, mesh)
	mesh_cold^ = {
		vertices = make([dynamic]Vertex, rm_allocator),
		indices  = make([dynamic]u32, rm_allocator)
	}

	vertex: Vertex
	for index in obj_mesh.indices {
		vertex.position = obj_mesh.positions[index]
		vertex.normal   = obj_mesh.normals[index]
		vertex.uv       = obj_mesh.texture_coordinates[index]
		
		append(&mesh_cold.vertices, vertex)
		append(&mesh_cold.indices, index)
	}

	mesh_hot := sparse_array_insert(&mesh_hots, mesh)

	mesh_hot.vertex_buffer = core.vk_vertex_buffer_create(vk.DeviceSize(len(mesh_cold.vertices) * size_of(Vertex)), &vk_allocator)
	core.vk_buffer_copy(transfer_pool, &mesh_hot.vertex_buffer, raw_data(mesh_cold.vertices[:]), &vk_allocator)
	mesh_hot.index_buffer = core.vk_index_buffer_create(vk.DeviceSize(len(mesh_cold.indices) * size_of(u32)), &vk_allocator)
	core.vk_buffer_copy(transfer_pool, &mesh_hot.index_buffer, raw_data(mesh_cold.indices[:]), &vk_allocator)
	mesh_hot.index_count = u32(len(mesh_cold.indices))

	for filepath, texture_type in texture_filepaths {
		if filepath == "" do continue

		mesh_hot.texture_types += {texture_type}
		path := sparse_array_insert(&textures[texture_type], mesh)
		path^ = filepath
		
		if filepath in texture_cache do continue
		
		texture_file, success := os.read_entire_file_from_filename(filepath)
		if !success {
			log.fatal("Invalid texture filepath")
			os.exit(-1)
		}
		defer delete(texture_file)
		
		image.set_flip_vertically_on_load(1)
		width, height, channels: i32
		parsed_data := image.load_from_memory(raw_data(texture_file), i32(len(texture_file)), &width, &height, &channels, 4)
		if channels != 4 {
			log.fatal("Unsupported texture format")
			os.exit(-1)
		}
		defer image.image_free(parsed_data)

		data := make([]u8, width * height * channels)
		defer delete(data)
		mem.copy(raw_data(data), parsed_data, len(data))

		location := u32(len(texture_cache))
		map_insert(&texture_cache, filepath, Texture{})
		texture := &texture_cache[filepath]
		texture.image = core.vk_texture_image_create(.OPTIMAL, vk.Extent3D{u32(width), u32(height), 1}, .R8G8B8A8_SRGB, &vk_allocator)
		core.vk_image_copy_staged(transfer_pool, &texture.image, data, &vk_allocator)
		texture.sampler = core.vk_sampler_create()
		texture.sample_location = location
	}

	return mesh
}

resource_manager_destroy_mesh :: proc(
	mesh: Mesh
) {
	using resource_manager
	ensure(initialised)
	ensure(sparse_array_contains(&mesh_hots, mesh))

	mesh_cold := sparse_array_get(&mesh_colds, mesh)
	delete(mesh_cold.vertices)
	delete(mesh_cold.indices)
	sparse_array_remove(&mesh_colds, mesh)

	mesh_hot := sparse_array_get(&mesh_hots, mesh)
	core.vk_buffer_destroy(&mesh_hot.vertex_buffer)
	core.vk_buffer_destroy(&mesh_hot.index_buffer)
	sparse_array_remove(&mesh_hots, mesh)

	append(&free_meshes, mesh)
}

resource_manager_get_mesh_cold :: proc(
	mesh: Mesh
) -> (
	mesh_hot: ^Mesh_Cold
) {
	using resource_manager
	ensure(initialised)
	ensure(sparse_array_contains(&mesh_colds, mesh))

	return sparse_array_get(&mesh_colds, mesh)
}

resource_manager_get_mesh_hot :: proc(
	mesh: Mesh
) -> (
	mesh_hot: ^Mesh_Hot
) {
	using resource_manager
	ensure(initialised)
	ensure(sparse_array_contains(&mesh_hots, mesh))

	return sparse_array_get(&mesh_hots, mesh)
}

resource_manager_get_texture :: proc(
	mesh:         Mesh,
	texture_type: Texture_Type
) -> (
	texture: ^Texture
) {
	using resource_manager
	assert(initialised)
	
	texture_array := &textures[texture_type]
	assert(sparse_array_contains(texture_array, mesh))

	return &texture_cache[sparse_array_get(texture_array, mesh)^]
}
