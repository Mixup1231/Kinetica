package core

import "core:log"

import la "core:math/linalg"

Camera_Vector :: enum {
	Front,
	Right,
	Up,
}

Frustum :: [6]Frustum_Plane
Frustum_Plane :: struct {
	normal: la.Vector3f32,
	d:      f32
}

Camera_3D :: struct {
	rotation:    la.Quaternionf32,
	projection:  la.Matrix4x4f32,
	position:    la.Vector3f32,
	sensitivity: [2]f32,
	aspect:      f32,
	near:        f32,
	far:         f32,
	fovy:        f32,
	speed:       f32
}

frustum_plane_normalize :: proc(
	frustum_plane: ^Frustum_Plane
) {
	ensure(frustum_plane != nil)

	length := la.length(frustum_plane.normal)
	frustum_plane.normal /= length
	frustum_plane.d      /= length
}

view_projection_get_frustum :: proc(
	view_projection: la.Matrix4f32
) -> (
	frustum: Frustum
) {
	view_projection := view_projection

	view_projection = la.transpose(view_projection)
	
	frustum[0] = {
		(view_projection[3] + view_projection[0]).xyz,
		(view_projection[3].w + view_projection[0].w)	
	}
	
	frustum[1] = {
		(view_projection[3] - view_projection[0]).xyz,
		(view_projection[3].w - view_projection[0].w)	
	}
		
	frustum[2] = {
		(view_projection[3] + view_projection[1]).xyz,
		(view_projection[3].w + view_projection[1].w)	
	}
		
	frustum[3] = {
		(view_projection[3] - view_projection[1]).xyz,
		(view_projection[3].w - view_projection[1].w)	
	}
		
	frustum[4] = {
		(view_projection[3] + view_projection[2]).xyz,
		(view_projection[3].w + view_projection[2].w)	
	}
		
	frustum[5] = {
		(view_projection[3] - view_projection[2]).xyz,
		(view_projection[3].w - view_projection[2].w)	
	}

	for &plane in frustum {
		frustum_plane_normalize(&plane)
	}
	
	return frustum
}

frustum_intersects_aabb :: proc(
	aabb:    AABB,
	frustum: ^Frustum
) -> (
	intersects: bool
) {
	ensure(frustum != nil)

	for &plane in frustum {
		positive := aabb_get_positive_vertex(aabb, plane.normal)
		distance := la.dot(plane.normal, positive) + plane.d
		
		if distance < 0 do return false
	}

	return true
}

camera_3d_create :: proc(
	aspect:      f32,
	fovy:        f32           = la.PI / 4,
	near:        f32           = 0.01,
	far:         f32           = 100,
	position:    la.Vector3f32 = {0, 0, 0},
	pitch:       f32           = 0,
	yaw:         f32           = 0,
	sensitivity: [2]f32        = {1, 1},
	speed:       f32           = 1
) -> (
	camera: Camera_3D
) {
	camera = {
		projection  = la.matrix4_perspective_f32(fovy, aspect, near, far),
		rotation    = la.quaternion_from_pitch_yaw_roll_f32(pitch, yaw, 0),
		position    = position,
		fovy        = fovy,
		aspect      = aspect,
		near        = near,
		far         = far,
		sensitivity = sensitivity,
		speed       = speed,
	}

	return camera
}

camera_3d_update :: proc(
	camera: ^Camera_3D,
	delta:  [2]f32,
) {
	if delta.x == 0 && delta.y == 0 do return	
	ensure(camera != nil)

	delta := delta
	delta.y *= -1 // NOTE(Mitchell): we flip y delta because the y-axis increases downward in Vulkan - wtf?

	angle := la.to_radians(delta.y / 20) * camera.sensitivity.y
	pitch := la.quaternion_angle_axis_f32(angle, {1, 0, 0})
	
	angle = la.to_radians(delta.x / 20) * camera.sensitivity.x
	yaw := la.quaternion_angle_axis_f32(angle, {0, 1, 0})
	
	camera.rotation = la.quaternion_mul_quaternion(pitch, camera.rotation)
	camera.rotation = la.quaternion_mul_quaternion(camera.rotation, yaw)
}

camera_3d_set_projection :: proc(
	camera: ^Camera_3D,
	fovy:   f32,
	aspect: f32,
	near:   f32,
	far:    f32
) {
	ensure(camera != nil)

	camera.projection = la.matrix4_perspective_f32(fovy, aspect, near, far)
}

camera_3d_get_view_projection :: proc(
	camera: ^Camera_3D
) -> (
	view: la.Matrix4x4f32
) {
	rotate := la.matrix4_from_quaternion_f32(la.quaternion_normalize(camera.rotation))	
		
	translate := la.identity_matrix(la.Matrix4f32)
	translate *= la.matrix4_translate_f32(-camera.position)

	view = rotate * translate

	return camera.projection * view
}

camera_3d_set_fov :: proc(
	camera: ^Camera_3D,
	fovy:   f32
) {
	ensure(camera != nil)
	
	camera.fovy = fovy
	camera_3d_set_projection(camera, camera.fovy, camera.aspect, camera.near, camera.far)
}

camera_3d_get_front :: proc(
	camera: ^Camera_3D
) -> (
	forward: la.Vector3f32
) {
	ensure(camera != nil)

	return la.quaternion_mul_vector3(camera.rotation, la.Vector3f32({0, 0, -1}))
}

camera_3d_get_right :: proc(
	camera: ^Camera_3D
) -> (
	right: la.Vector3f32
) {
	ensure(camera != nil)

	return la.quaternion_mul_vector3(camera.rotation, la.Vector3f32({1, 0, 0}))
}

camera_3d_get_up :: proc(
	camera: ^Camera_3D
) -> (
	up: la.Vector3f32
) {
	ensure(camera != nil)

	return la.quaternion_mul_vector3(camera.rotation, la.Vector3f32({0, 1, 0}))
}

camera_3d_get_vectors :: proc(
	camera: ^Camera_3D
) -> (
	vectors: [Camera_Vector]la.Vector3f32
) {
	ensure(camera != nil)

	orientation := la.quaternion_inverse(camera.rotation)

	vectors[.Front] = la.quaternion_mul_vector3(orientation, la.Vector3f32({0, 0, -1}))
	vectors[.Right] = la.quaternion_mul_vector3(orientation, la.Vector3f32({1, 0, 0}))
	vectors[.Up]    = la.quaternion_mul_vector3(orientation, la.Vector3f32({0, -1, 0}))

	return vectors
}
