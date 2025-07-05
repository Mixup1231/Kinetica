package obj_loader

Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
	uv:       [2]f32,
}

Mesh :: distinct Mesh_Data
Submesh :: distinct Mesh_Data
Mesh_Data :: struct {
	vertices: []Vertex,
	indices:  []u32,
}

Object :: union {
	Mesh,
	map[string]Submesh,
}

File :: struct {
	objects: map[string]Object
}

load_file :: proc(
	filepath: string,
	allocator := context.allocator
) -> (
	file: File
) {
	
	
	return file
}
