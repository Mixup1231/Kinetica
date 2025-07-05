package obj_loader

OBJ_Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
	uv:       [2]f32,
}

OBJ_Mesh :: distinct OBJ_Mesh_Data
OBJ_Submesh :: distinct OBJ_Mesh_Data
OBJ_Mesh_Data :: struct {
	vertices: []OBJ_Vertex,
	indices:  []u32,
}

OBJ_Object :: union {
	OBJ_Mesh,
	map[string]OBJ_Submesh,
}

OBJ_File :: struct {
	objects: [dynamic]OBJ_Object
}

obj_load_file :: proc(
	filepath: string,
	allocator := context.allocator
) -> (
	file: OBJ_File
) {
	
	
	return file
}
