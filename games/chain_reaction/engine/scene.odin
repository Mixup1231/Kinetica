package engine

import "core:mem"

import "../../../kinetica/core"

// TODO(Mitchell):
// Add Direction_Light
// Rename Light -> Point_Light
// Add insert_point_light
// Add get_point_light
// Add get_direction_light
// Add insert_entity *takes callback for construction and destruction
// Add insert_static_mesh
// Add register_mesh_component *takes mesh and transform
// Add register_script_component

Entity_ID :: u32
Light_ID  :: u32

Component_Types :: distinct bit_set[Component_Type]
Component_Type :: enum {
	Mesh,
	Transform,
	Script,
}

Script :: struct {
	update:       proc(f32, ^Entity),
	fixed_update: proc(f32, ^Entity),
}

Entity :: struct {
	mesh:            Mesh,
	transform:       core.Transform,
	script:          Script,
	component_types: Component_Types,
}

// NOTE(Mitchell): Remember to pad correctly
Light :: struct #align(16) {
	position: [4]f32,
	color:    [4]f32,
}

Scene :: struct {
	entities:         Sparse_Array(Entity_ID, Entity, Max_Entities),
	free_entities:    [dynamic]Entity_ID,
	meshes:           map[Mesh]Sparse_Array(Entity_ID, Entity_ID, Max_Entities),
	static_meshes:    map[Mesh][dynamic]core.Transform,
	point_lights:     Sparse_Array(Light_ID, Light, Max_Lights),
	ambient_strength: f32,
	ambient_color:    [3]f32,
	s_allocator:      mem.Allocator,
}

scene_create :: proc(
	allocator := context.allocator
) -> (
	scene: Scene,
) {
	context.allocator = allocator

	scene = {
		entities         = sparse_array_create(Entity_ID, Entity, Max_Entities),
		free_entities    = make([dynamic]Entity_ID),
		meshes           = make(map[Mesh]Sparse_Array(Entity_ID, Entity_ID, Max_Entities)),
		static_meshes    = make(map[Mesh][dynamic]core.Transform),
		point_lights     = sparse_array_create(Light_ID, Light, Max_Lights),
		ambient_strength = 0.1,
		ambient_color    = {1, 1, 1},
		s_allocator      = allocator,
	}

	return scene
}

scene_destroy :: proc(
	scene: ^Scene
) {
	assert(scene != nil)

	sparse_array_destroy(&scene.entities)
	delete(scene.free_entities)
	
	for mesh, &sparse_array in scene.meshes {
		sparse_array_destroy(&sparse_array)
	}
	delete(scene.meshes)
	
	for mesh, &transform_array in scene.static_meshes {
		delete(transform_array)
	}
	delete(scene.static_meshes)
	
	sparse_array_destroy(&scene.point_lights)
}

scene_update_entities :: proc(
	scene: ^Scene,
	dt:    f32
) {
	assert(scene != nil)

	for &entity in sparse_array_slice(&scene.entities) {
		if .Script in entity.component_types {
			if entity.script.update != nil do entity.script.update(dt, &entity)
		}
	}
}

scene_fixed_update_entities :: proc(
	scene: ^Scene,
	ts:    f32
) {
	assert(scene != nil)
	
	for &entity in sparse_array_slice(&scene.entities) {
		if .Script in entity.component_types {
			if entity.script.fixed_update != nil do entity.script.fixed_update(ts, &entity)
		}
	}
}
