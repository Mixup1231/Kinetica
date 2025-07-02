package core

import la "core:math/linalg"

AABB :: struct {
	min: la.Vector3f32,
	max: la.Vector3f32,
}

Sphere :: struct {
	position: la.Vector3f32,
	radius:   f32,
}

aabb_get_positive_vertex :: proc(
	aabb:   AABB,
	normal: la.Vector3f32,	
) -> (
	positive_vertex: la.Vector3f32
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
