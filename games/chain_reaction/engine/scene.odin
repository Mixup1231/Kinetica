package engine

import "../../../kinetica/core"

// NOTE(Mitchell): Remember to pad correctly
Light :: struct #align(16) {
	position: [4]f32,
	color:    [4]f32,
}

Scene :: struct {
	mesh: Mesh
}
