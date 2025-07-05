package obj_loader

import "core:os"
import "core:fmt"
import "core:strings"
import "core:strconv"

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
		i = u32(strconv.atoi(token_indices[0]))
	}
	
	if token_indices[1] != "" {
		group.vertex_attributes += {.Normal}
		j = u32(strconv.atoi(token_indices[1]))
	}
	
	if token_indices[2] != "" {
		group.vertex_attributes += {.Texture_Coordinate}
		k = u32(strconv.atoi(token_indices[2]))
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

	for line in lines {		
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
