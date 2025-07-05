package main

import "core:fmt"
import "core:strings"

import "../../kinetica/extensions/obj"

main :: proc() {
	file, _ := obj.read_file("./examples/obj/test.obj")

	fmt.println(file.positions)
	fmt.println(file.normals)
	fmt.println(file.texture_coordinates)
	
	for name, object in file.objects {
		fmt.println(name)
		
		for _, group in object.groups {
			fmt.println(group)
		}
	}
}
