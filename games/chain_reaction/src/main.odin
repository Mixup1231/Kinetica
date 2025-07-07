package main

import "core:fmt"

import "../../../kinetica/core"

import "../engine"

main :: proc() {
	core.window_create(800, 600, "Oh my Gourd!")
	defer core.window_destroy()

	engine.resource_manager_init()
	defer engine.resource_manager_destory()

	mesh := engine.resource_manager_load_mesh("games/chain_reaction/assets/models/test.obj", {})
	defer engine.resource_manager_destroy_mesh(mesh)

	for !core.window_should_close() {
		core.window_poll()
	}
}
