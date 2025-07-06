package core

import "core:log"
import la "core:math/linalg"

AABB :: struct {
	min: [3]f32,
	max: [3]f32,
}

Sphere :: struct {
	position: [3]f32,
	radius:   f32,
}

Transform :: struct {
	position: [3]f32,
	scale:    [3]f32,
	rotation: la.Quaternionf32,
}

aabb_from_positions :: proc(
	positions: [][3]f32
) -> (
	aabb: AABB
) {
	aabb.min = {max(f32), max(f32), max(f32)}
	aabb.max = {min(f32), min(f32), min(f32)}

	for position in positions {
		aabb.min = la.min(aabb.min, position)
		aabb.max = la.max(aabb.max, position)
	}

	return aabb
}

aabb_get_origin :: proc(
	aabb: AABB
) -> (
	origin: [3]f32
) {
	return {
		aabb.max.x - (aabb.max.x - aabb.min.x) * 0.5,
		aabb.max.y - (aabb.max.y - aabb.min.y) * 0.5,
		aabb.max.z - (aabb.max.z - aabb.min.z) * 0.5,
	}
}

aabb_get_positive_vertex :: proc(
	aabb:   AABB,
	normal: [3]f32,
) -> (
	positive_vertex: [3]f32
) {
	return {
		aabb.max.x if normal.x >= 0 else aabb.min.x,
		aabb.max.y if normal.y >= 0 else aabb.min.y,
		aabb.max.z if normal.z >= 0 else aabb.min.z,
	}
}

aabb_intersects_aabb :: proc(
	a: AABB,
	b: AABB
) -> (
	intersects: bool
) {
	return !(a.max.x < b.min.x || a.min.x > b.max.x ||
	 		 a.max.y < b.min.y || a.min.y > b.max.y ||
	 		 a.max.z < b.min.z || a.min.z > b.max.z)
}

aabb_intersects_sphere :: proc(
	aabb:   AABB,
	sphere: Sphere
) -> (
	intersects: bool
) {
	closest_point    := la.clamp(sphere.position, aabb.min, aabb.max)
	distance_squared := la.length2(sphere.position - closest_point)

	return distance_squared <= (sphere.radius * sphere.radius)
}

sphere_intersects_sphere :: proc(
	a: Sphere,
	b: Sphere
) -> (
	intersects: bool
) {
	radius_squard    := (b.radius + a.radius) * (b.radius + a.radius)
	distance_squared := la.length2(b.position - a.position)
	
	return distance_squared <= radius_squard
}

transform_get_matrix :: proc(
	transform: ^Transform
) -> (
	m: matrix[4, 4]f32
) {
	ensure(transform != nil)

	m = la.identity_matrix(la.Matrix4f32)

	scale       := la.matrix4_scale_f32(transform.scale)
	rotation    := la.matrix4_from_quaternion_f32(la.quaternion_normalize(transform.rotation))
	translation := la.matrix4_translate_f32(transform.position)

	m *= translation
	m *= rotation
	m *= scale

	return m
}

transform_scale :: proc(
	transform: ^Transform,
	scale:     [3]f32,
) {
	ensure(transform != nil)
	
	transform.scale += scale
}

transform_rotate :: proc(
	transform: ^Transform,
	axis:      [3]f32,
	angle:     f32
) {
	ensure(transform != nil)

	rotation := la.quaternion_angle_axis_f32(angle, axis)
	transform.rotation = la.quaternion_mul_quaternion(transform.rotation, rotation)
}

transform_translate :: proc(
	transform:   ^Transform,
	translation: [3]f32,
) {
	ensure(transform != nil)

	transform.position += translation
}
