package engine

import "core:mem"
import "core:log"

import "../../../kinetica/core"

// TODO(Mitchell):
// Add Direction_Light
// Add get_direction_light
// Add insert_static_mesh

Entity_ID :: u32
Light_ID  :: u32

Component_Types :: distinct bit_set[Component_Type]
Component_Type :: enum {
	Mesh,
	Transform,
	Script,
	Physics
}

Physics ::struct {
	velocity:  [3]f32
}

Script :: struct {
	update:       proc(f32, ^Entity),
	fixed_update: proc(f32, ^Entity),
}

Entity_Tag :: enum {
	None,
	Pumpkin,
}

Entity :: struct {
	mesh:            Mesh,
	transform:       core.Transform,
	script:          Script,
	physics:         Physics,
	component_types: Component_Types,
	tag:             Entity_Tag,
	id:              Entity_ID,
	couple:          ^Entity, // Im using  this to couple the head and bot of pumpkin, bit of a bandaid
}

// NOTE(Mitchell): Remember to pad correctly
Point_Light :: struct #align(16) {
	position: [4]f32,
	color:    [4]f32,
}

Scene :: struct {
	entities:          Sparse_Array(Entity_ID, Entity, Max_Entities),
	free_entities:     [dynamic]Entity_ID,
	meshes:            map[Mesh]Sparse_Array(Entity_ID, Entity_ID, Max_Entities),
	static_meshes:     map[Mesh][dynamic]core.Transform,
	point_lights:      [Max_Point_Lights]Point_Light,
	point_light_count: u32,
	ambient_strength:  f32,
	ambient_color:     [3]f32,
	s_allocator:       mem.Allocator,
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
		ambient_strength = 0.1,
		ambient_color    = {1, 1, 1},
		s_allocator      = allocator,
	}

	for i: Entity_ID = Max_Entities; i > 0; i -= 1 {
		append(&scene.free_entities, i)
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
}

scene_insert_point_light :: proc(
	scene: ^Scene
) -> (
	light_id: Light_ID,
	light:    ^Point_Light
) {
	assert(scene.point_light_count < Max_Point_Lights)

	light_id = scene.point_light_count
	light    = &scene.point_lights[light_id]
	scene.point_light_count += 1

	return light_id, light
}

scene_get_point_light :: proc(
	scene:    ^Scene,
	light_id: Light_ID
) -> (
	light: ^Point_Light
) {
	assert(scene != nil)
	assert(light_id < scene.point_light_count)

	return &scene.point_lights[light_id]
}

scene_insert_entity :: proc(
	scene: ^Scene,
	setup: proc(^Entity) = nil,
) -> (
	entity_id: Entity_ID,
	entity:    ^Entity,
) {
	assert(scene != nil)
	assert(len(scene.free_entities) > 0)

	entity_id = scene.free_entities[len(scene.free_entities)-1]
	unordered_remove(&scene.free_entities, len(scene.free_entities)-1)

	entity = sparse_array_insert(&scene.entities, entity_id)
	if setup != nil do setup(entity)
	entity.id = entity_id

	return entity_id, entity
}

scene_destroy_entity ::proc(
	scene: ^Scene,
	entity_id: Entity_ID,
	entity:  ^Entity,
	cleanup: proc(^Entity) = nil,
) {
	assert(scene != nil)
	assert(entity != nil)

	sparse_array_remove(&scene.meshes[entity.mesh],entity_id)
	sparse_array_remove(&scene.entities, entity_id)
	append(&scene.free_entities, entity_id)
	if cleanup != nil && entity != nil{
		cleanup(entity)
	}
}

scene_get_entity :: proc(
	scene: ^Scene,
	entity_id: Entity_ID
) -> (
	entity: ^Entity
) {
	assert(scene != nil)
	assert(sparse_array_contains(&scene.entities, entity_id))

	return sparse_array_get(&scene.entities, entity_id)
}

scene_register_mesh_component :: proc(
	scene:     ^Scene,
	entity_id: Entity_ID,
	mesh:      Mesh,
	transform: core.Transform
) {
	assert(scene != nil)
	assert(sparse_array_contains(&scene.entities, entity_id))

	context.allocator = scene.s_allocator

	if mesh in scene.meshes {
		sparse_array := &scene.meshes[mesh]
		assert(!sparse_array_contains(sparse_array, entity_id))

		sparse_array_insert(sparse_array, entity_id)^ = entity_id
	} else {
		sparse_array := sparse_array_create(Entity_ID, Entity_ID, Max_Entities)
		map_insert(&scene.meshes, mesh, sparse_array)
		sparse_array_insert(&scene.meshes[mesh], entity_id)^ = entity_id
	}

	entity := sparse_array_get(&scene.entities, entity_id)
	entity.mesh = mesh
	entity.transform = transform
	entity.component_types += {.Mesh, .Transform}
}

scene_register_script_component :: proc(
	scene:     ^Scene,
	entity_id: Entity_ID,
	script:    Script
) {
	assert(scene != nil)
	assert(sparse_array_contains(&scene.entities, entity_id))

	entity := sparse_array_get(&scene.entities, entity_id)
	entity.script = script
	entity.component_types += {.Script}
}

scene_register_physics_component :: proc(
	scene:     ^Scene,
	entity_id: Entity_ID,
	physics:   Physics,
) {
	assert(scene != nil)
	assert(sparse_array_contains(&scene.entities, entity_id))

	entity := sparse_array_get(&scene.entities, entity_id)
	entity.physics= physics
	entity.component_types += {.Physics}
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

scene_update_physics_entities :: proc(
	scene: ^Scene,
	ts:     f32,
) {
	assert(scene != nil)

	for &entity in sparse_array_slice(&scene.entities) {
		if .Physics in entity.component_types {
			entity.transform.position += entity.physics.velocity * ts

			// Floor collider
			if entity.transform.position.y > -1 {
				entity.physics.velocity = {0, 0, 0}
				continue
			}

			// Gravity
			entity.physics.velocity.y += 1
		}
	}
}
