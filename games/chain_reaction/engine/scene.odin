package engine

import "../../../kinetica/core"

// NOTE(Mitchell): Remember to pad correctly
Light :: struct #align(16) {
	position: [4]f32,
	color:    [4]f32,
}

Scene :: struct {
	mesh: Mesh,
	ambient_strength: f32,
	ambient_color:    [3]f32,
}
