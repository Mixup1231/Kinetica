package obj

// TODO(Mitchell):
// Add way to triangulate quads?
// Add material support

import "core:os"
import "core:mem"
import "core:strings"
import "core:strconv"
import la "core:math/linalg"

Line_Type :: enum {
	Comment,
	Object,
	Group,
	Material,
	Position,
	Normal,
	Texture_Coordinate,
	Face,
	Invalid,
}

Vertex_Attributes :: distinct bit_set[Vertex_Attribute]
Vertex_Attribute :: enum {
	Position,
	Normal,
	Texture_Coordinate,
}

Mesh :: struct {
	positions:           [dynamic][3]f32,
	normals:             [dynamic][3]f32,
	texture_coordinates: [dynamic][2]f32,
	indices:             [dynamic]u32,
	vertex_attributes:   Vertex_Attributes,
}

Group :: struct {
	indices:           [dynamic][3]u32,
	vertex_attributes: Vertex_Attributes,
}

Object :: struct {
	groups: map[string]Group,
}

File :: struct {
	positions:           [dynamic][3]f32,
	normals:             [dynamic][3]f32,
	texture_coordinates: [dynamic][2]f32,
	objects:             map[string]Object
}

get_line_type :: proc(
	token: string
) -> (
	line_type: Line_Type
) {
	if token == "v" do return .Position
	if token == "vn" do return .Normal
	if token == "vt" do return .Texture_Coordinate
	if token == "f" do return .Face
	if token == "g" do return .Group
	if token == "o" do return .Object
	if token == "usemtl" do return .Material
	if token == "#" do return .Comment
	
	return .Invalid
}

tokenize_line :: proc(
	line: string,
	allocator := context.allocator
) -> (
	tokens: []string
) {
	context.allocator = allocator
	tokens, _ = strings.split(line, " ")

	return tokens
}

tokenize_face_token :: proc(
	token: string,
	allocator := context.allocator
) -> (
	tokens: []string,
) {
	context.allocator = allocator
	
	if strings.contains(token, "/") {
		tokens, _ = strings.split(token, "/")
	} else {
		tokens = make([]string, 3)
		tokens[0] = token
	}

	return tokens
}

get_line_name :: proc(
	line:      string,
	line_type: Line_Type
) -> (
	name: string
) {
	#partial switch(line_type) {
	case .Object, .Group:
		return line[2:]
	case .Material:
		return line[len("usemtl")+1:]
	}

	return ""
}

parse_positions :: proc(
	tokens:    []string,
	positions: ^[dynamic][3]f32,
	allocator := context.allocator
) {
	context.allocator = allocator

	positions := positions

	append(
		positions,
		[3]f32{
			f32(strconv.atof(tokens[0])),
			f32(strconv.atof(tokens[1])),
			f32(strconv.atof(tokens[2])),
		}
	)
}

parse_normals :: proc(
	tokens:  []string,
	normals: ^[dynamic][3]f32,
	allocator := context.allocator
) {
	context.allocator = allocator

	normals := normals

	append(
		normals,
		[3]f32{
			f32(strconv.atof(tokens[0])),
			f32(strconv.atof(tokens[1])),
			f32(strconv.atof(tokens[2])),
		}
	)
}

parse_texture_coordinates :: proc(
	tokens:  []string,
	normals: ^[dynamic][2]f32,
	allocator := context.allocator
) {
	context.allocator = allocator

	normals := normals

	append(
		normals,
		[2]f32{
			f32(strconv.atof(tokens[0])),
			f32(strconv.atof(tokens[1])),
		}
	)
}

parse_face_token :: proc(
	face_token: string,
	group:      ^Group,
	allocator := context.allocator
) {
	context.allocator = allocator
	
	token_indices := tokenize_face_token(face_token)
	defer delete(token_indices)

	i, j, k: u32
	
	if token_indices[0] != "" {
		group.vertex_attributes += {.Position}
		i = u32(strconv.atoi(token_indices[0])) - 1
	}
	
	if token_indices[1] != "" {
		group.vertex_attributes += {.Texture_Coordinate}
		j = u32(strconv.atoi(token_indices[1])) - 1
	}
	
	if token_indices[2] != "" {
		group.vertex_attributes += {.Normal}
		k = u32(strconv.atoi(token_indices[2])) - 1
	}

	append(&group.indices, [3]u32{i, j, k})
}

read_file :: proc(
	filepath: string,
	allocator := context.allocator
) -> (
	file:    File,
	success: bool
) {
	context.allocator = allocator

	data, read_file := os.read_entire_file(filepath)
	if !read_file do return file, false
	defer delete(data)	

	lines, error := strings.split_lines(transmute(string)data)
	if error != .None do return file, false
	defer delete(lines)
		
	file = {
		positions           = make([dynamic][3]f32),
		normals             = make([dynamic][3]f32),
		texture_coordinates = make([dynamic][2]f32),
		objects             = make(map[string]Object)
	}

	set_current :: proc(
		x:        ^u32,
		x_buffer: []u8,
		current:  ^string
	) {
		name := strconv.itoa(x_buffer, int(x^))
		current^ = name
		x^ += 1
	}

	i, j: u32 = 1, 1           // used in case "o" or "g" don't provide names
	i_buffer, j_buffer: [10]u8 // buffers for converting i and j to strings (10 digits is enough to hold any u32)
	current_object, current_group: string

	count: u32

	for line in lines {
		if strings.contains(line, "vt") do count += 1
		
		tokens := tokenize_line(line)
		defer delete(tokens)

		line_type := get_line_type(tokens[0])
		
		switch (line_type) {
		case .Comment, .Material, .Invalid:
			continue
		case .Object:
			object_name := get_line_name(line, .Object)
			if object_name == "" {
				set_current(&i, i_buffer[:], &current_object)
			} else {
				current_object = object_name
			}

			object: Object = {
				groups = make(map[string]Group)
			}
			file.objects[current_object] = object
		case .Group:
			if current_object == "" {
				set_current(&i, i_buffer[:], &current_object)
				object: Object = {
					groups = make(map[string]Group)
				}
				file.objects[current_object] = object
			}
			
			group_name := get_line_name(line, .Group)
			if group_name == "" {
				set_current(&j, j_buffer[:], &current_group)
			} else {
				current_group = group_name
			}
			
			group: Group = {
				indices           = make([dynamic][3]u32),
				vertex_attributes = {}
			}
			object := &file.objects[current_object]
			object.groups[current_group] = group
		case .Face:
			if current_object == "" {
				set_current(&i, i_buffer[:], &current_object)
				object: Object = {
					groups = make(map[string]Group)
				}
				file.objects[current_object] = object
			}
			
			if current_group == "" {
				set_current(&j, j_buffer[:], &current_group)
				group: Group = {
					indices           = make([dynamic][3]u32),
					vertex_attributes = {}
				}
				object := &file.objects[current_object]
				object.groups[current_group] = group
			}
			
			for token in tokens[1:] {
				object := &file.objects[current_object]
				group := &object.groups[current_group]
				parse_face_token(token, group)
			}
		case .Position:
			parse_positions(tokens[1:], &file.positions)			
		case .Normal:
			parse_normals(tokens[1:], &file.normals)			
		case .Texture_Coordinate:
			parse_texture_coordinates(tokens[1:], &file.texture_coordinates)
		}
	}

	return file, true
}

destroy_file :: proc(
	file: ^File
) {
	ensure(file != nil)

	delete(file.positions)
	delete(file.normals)
	delete(file.texture_coordinates)

	for _, &object in file.objects {
		for _, &group in object.groups {
			delete(group.indices)
		}
		delete(object.groups)
	}
	delete(file.objects)
}

get_vertex_positions_by_objects :: proc(
	file:    ^File,
	objects: ..string,
	allocator := context.allocator
) -> (
	positions: [dynamic][3]f32,
	indices:   [dynamic]u32
) {
	context.allocator = allocator
	ensure(file != nil)

	positions = make([dynamic][3]f32)
	indices   = make([dynamic]u32)

	faces := make(map[u32]u32)
	defer delete(faces)

	index_count: u32
	for object_name in objects {
		if object_name not_in file.objects do continue

		for _, group in file.objects[object_name].groups {
			if .Position not_in group.vertex_attributes do continue

			for ptn in group.indices {
				if ptn.x in faces {
					append(&indices, faces[ptn.x])
				} else {
					append(&indices, index_count)
					append(&positions, file.positions[ptn.x])
					faces[ptn.x] = index_count
					index_count += 1
				}
			}
		}
	}

	return positions, indices
}

get_all_vertex_positions :: proc(
	file: ^File,
	allocator := context.allocator
) -> (
	positions: [dynamic][3]f32,
	indices:   [dynamic]u32
) {
	context.allocator = allocator
	ensure(file != nil)

	positions = make([dynamic][3]f32)
	indices   = make([dynamic]u32)

	faces := make(map[u32]u32)
	defer delete(faces)

	index_count: u32
	for _, object in file.objects {
		for _, group in object.groups {
			if .Position not_in group.vertex_attributes do continue

			for ptn in group.indices {
				if ptn.x in faces {
					append(&indices, faces[ptn.x])
				} else {
					append(&indices, index_count)
					append(&positions, file.positions[ptn.x])
					faces[ptn.x] = index_count
					index_count += 1
				}
			}
		}
	}

	return positions, indices
}

get_mesh_by_objects :: proc(
	file:    ^File,
	objects: ..string,
	allocator := context.allocator
) -> (
	mesh: Mesh
) {
	context.allocator = allocator
	ensure(file != nil)
	
	mesh = {
		positions           = make([dynamic][3]f32),
		normals             = make([dynamic][3]f32),
		texture_coordinates = make([dynamic][2]f32),
		indices             = make([dynamic]u32),
	}

	calculate_normals: bool
	index_count: u32
	
	for object_name in objects {
		if object_name not_in file.objects do continue
		
		for _, group in file.objects[object_name].groups {
			for ptn in group.indices {
				append(&mesh.indices, index_count)
				
				if .Position in group.vertex_attributes {
					append(&mesh.positions, file.positions[ptn.x])
				} else {
					append(&mesh.positions, [3]f32{0, 0, 0})
				}

				if .Texture_Coordinate in group.vertex_attributes {
					append(&mesh.texture_coordinates, file.texture_coordinates[ptn.y])
				} else {
					append(&mesh.texture_coordinates, [2]f32{0, 0})
				}
				
				if .Normal in group.vertex_attributes {
					append(&mesh.normals, file.normals[ptn.z])
				} else {
					append(&mesh.normals, [3]f32{0, 0, 0})
					calculate_normals = true
				}				
				index_count += 1
			}
			mesh.vertex_attributes += group.vertex_attributes
		}
	}

	if calculate_normals {
		mem.set(raw_data(mesh.normals[:]), 0, len(mesh.normals) * 3)
		for i in 0..<len(mesh.indices) / 3 {
			i0 := mesh.indices[i*3 + 0]
			i1 := mesh.indices[i*3 + 1]
			i2 := mesh.indices[i*3 + 2]

			p0 := mesh.positions[i0]
			p1 := mesh.positions[i1]
			p2 := mesh.positions[i2]

			e1 := p1 - p0
			e2 := p2 - p0

			n := la.cross(e1, e2)

			mesh.normals[i0] = mesh.normals[i0] + n
			mesh.normals[i1] = mesh.normals[i1] + n
			mesh.normals[i2] = mesh.normals[i2] + n
		}
		for &normal in mesh.normals do normal = la.normalize(normal)
	}
	
	return mesh
}

get_mesh :: proc(
	file:    ^File,
	allocator := context.allocator
) -> (
	mesh: Mesh
) {
	context.allocator = allocator
	ensure(file != nil)

	mesh = {
		positions           = make([dynamic][3]f32),
		normals             = make([dynamic][3]f32),
		texture_coordinates = make([dynamic][2]f32),
		indices             = make([dynamic]u32),
	}

	calculate_normals: bool
	index_count: u32
	
	for _, object in file.objects {
		for _, group in object.groups {
			for ptn in group.indices {				
				append(&mesh.indices, index_count)
				
				if .Position in group.vertex_attributes {
					append(&mesh.positions, file.positions[ptn.x])
				} else {
					append(&mesh.positions, [3]f32{0, 0, 0})
				}

				if .Texture_Coordinate in group.vertex_attributes {
					append(&mesh.texture_coordinates, file.texture_coordinates[ptn.y])
				} else {
					append(&mesh.texture_coordinates, [2]f32{0, 0})
				}
				
				if .Normal in group.vertex_attributes {
					append(&mesh.normals, file.normals[ptn.z])
				} else {
					append(&mesh.normals, [3]f32{0, 0, 0})
					calculate_normals = true
				}
				index_count += 1
			}
			mesh.vertex_attributes += group.vertex_attributes
		}
	}

	if calculate_normals {
		mem.set(raw_data(mesh.normals[:]), 0, len(mesh.normals) * 3)
		for i in 0..<len(mesh.indices) / 3 {
			i0 := mesh.indices[i*3 + 0]
			i1 := mesh.indices[i*3 + 1]
			i2 := mesh.indices[i*3 + 2]

			p0 := mesh.positions[i0]
			p1 := mesh.positions[i1]
			p2 := mesh.positions[i2]

			e1 := p1 - p0
			e2 := p2 - p0

			n := la.cross(e1, e2)

			mesh.normals[i0] = mesh.normals[i0] + n
			mesh.normals[i1] = mesh.normals[i1] + n
			mesh.normals[i2] = mesh.normals[i2] + n
		}
		for &normal in mesh.normals do normal = la.normalize(normal)
	}
	
	return mesh
}

destory_mesh :: proc(
	mesh: ^Mesh
) {
	ensure(mesh != nil)

	delete(mesh.positions)
	delete(mesh.normals)
	delete(mesh.texture_coordinates)
	delete(mesh.indices)
}
