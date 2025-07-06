package main

import "core:log"
import "core:time"
import "core:math"
import la "core:math/linalg"

import "../../kinetica/core"
import "../../kinetica/extensions/obj"

import vk "vendor:vulkan"

Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
	uv:       [2]f32,
}

Ubo :: struct {
	proj:           la.Matrix4f32,
	model:          la.Matrix4f32,
	position:       la.Vector4f32,
	light_position: la.Vector4f32,
	light_color:    la.Vector4f32,
}

Frames_In_Flight : u32 : 3
Image_Width :: 512
Image_Height :: 512

Application :: struct {
	camera:            core.Camera_3D,
	vk_allocator:      core.VK_Allocator,
	sampler:           vk.Sampler,
	data:              [Image_Width*Image_Height*4]u8,
	image:             core.VK_Image,
	depth_format:      vk.Format,
	depth_image:       core.VK_Image,
	graphics_pool:     core.VK_Command_Pool,
	transfer_pool:     core.VK_Command_Pool,
	command_buffers:   []core.VK_Command_Buffer,
	image_available:   []vk.Semaphore,
	render_finished:   []vk.Semaphore,
	block_until:       []vk.Fence,
	vertex_buffer:     core.VK_Buffer,
	index_buffer:      core.VK_Buffer,
	descriptor_pool:   vk.DescriptorPool,
	descriptor_layout: vk.DescriptorSetLayout,
	descriptor_sets:   []vk.DescriptorSet,
	uniform_buffer:    core.VK_Buffer,
	pipeline:          vk.Pipeline,
	pipeline_layout:   vk.PipelineLayout,
	cube_vertices:     [dynamic]Vertex,
	cube_indices:      [dynamic]u32,
	ubo:               Ubo,
}
application: Application

create_depth_image :: proc(
	extent: vk.Extent2D
) {
	using application
	
	if depth_image.handle != 0 do core.vk_image_destroy(&depth_image)	
	
	depth_image = core.vk_depth_image_create(
		depth_format,
		.OPTIMAL,
		{
			width = extent.width,
			height = extent.height,
			depth = 1
		},
		{.DEPTH_STENCIL_ATTACHMENT},
		&vk_allocator
	)
}

application_create :: proc() {	
	using application
	
	core.window_create(800, 600, "Obj example")
		
	core.vk_swapchain_set_recreation_callback(create_depth_image)
	extent := core.vk_swapchain_get_extent()

	core.input_set_mouse_mode(.Locked)

	camera = core.camera_3d_create(f32(extent.width)/f32(extent.height), fovy = la.to_radians(f32(60)))
	
	transfer_pool   = core.vk_command_pool_create(.Transfer)
	graphics_pool   = core.vk_command_pool_create(.Graphics)
	command_buffers = core.vk_command_buffer_create(graphics_pool, .PRIMARY, Frames_In_Flight)
	image_available = core.vk_semaphore_create(Frames_In_Flight)
	block_until     = core.vk_fence_create(true, Frames_In_Flight)
	
	swapchain_image_count := core.vk_swapchain_get_image_count()
	render_finished = core.vk_semaphore_create(swapchain_image_count)
	vk_allocator    = core.vk_allocator_get_default()
	
	mip_levels := core.vk_extent_get_mip_levels({Image_Width, Image_Height})
	sampler = core.vk_sampler_create(max_lod = f32(mip_levels))
	image   = core.vk_texture_image_create(.OPTIMAL, {Image_Width, Image_Height, 1}, .R8G8B8A8_SRGB, &vk_allocator, mip_levels)

	transition := core.vk_command_buffer_begin_single(transfer_pool)
	core.vk_command_image_barrier(
		command_buffer  = transition,
		image           = &image,
		new_layout      = .TRANSFER_DST_OPTIMAL,
		dst_access_mask = {.TRANSFER_WRITE},
		src_stage_mask  = {.TOP_OF_PIPE},
		dst_stage_mask  = {.TRANSFER},
		subresource_range = image.subresource_range
	)
	core.vk_command_buffer_end_single(transition)

	c := complex(-0.8, 0.156)
	zoom := 4.5

	scale_x := 3.0 / zoom
	scale_y := 2.0 / zoom
	
	hsv_to_rgb :: proc(h: f64, s: f64, v: f64) -> (f64, f64, f64) {
		hh := math.mod(h, 360.0) / 60.0;
		i := int(hh);
		ff := hh - f64(i);
	
		p := v * (1.0 - s);
		q := v * (1.0 - s * ff);
		t := v * (1.0 - s * (1.0 - ff));
	
		switch i {
		case 0: return v, t, p;
		case 1: return q, v, p;
		case 2: return p, v, t;
		case 3: return p, q, v;
		case 4: return t, p, v;
		case 5: return v, p, q;
		case: return 0.0, 0.0, 0.0; // fallback
		}
	}
	
	max_iterations := 100
	for y in 0..<Image_Height {
		for x in 0..<Image_Width {
			zx := (f64(x) / f64(Image_Width) - 0.5) * scale_x + real(c)
			zy := (f64(y) / f64(Image_Height) - 0.5) * scale_y + imag(c)

			i := 0
			for zx * zx + zy * zy < 4.0 && i < max_iterations {
				tmp := zx * zx - zy * zy + real(c)
				zy = 2.0 * zx * zy + imag(c)
				zx = tmp
				i += 1
			}

			index := (y * Image_Width + x) * 4

			if i == max_iterations {
				data[index + 0] = 25
				data[index + 1] = 25
				data[index + 2] = 25
			} else {
				z_mag := math.sqrt(zx * zx + zy * zy);
				nu := f64(i) + 1.0 - math.log2(math.log2(z_mag));
				t := nu / f64(max_iterations);
				
				hue := 360.0 * t;
				r, g, b := hsv_to_rgb(hue, 1.0, 1.0);
				
				data[index + 0] = u8(clamp(r * 255.0, 0.0, 255.0))
				data[index + 1] = u8(clamp(g * 255.0, 0.0, 255.0))
				data[index + 2] = u8(clamp(b * 255.0, 0.0, 255.0))
			}
			data[index + 3] = 255
		} 
	}
		
	core.vk_image_copy_staged(transfer_pool, &image, data[:], &vk_allocator)
	
	core.vk_image_generate_mip_maps(graphics_pool, &image)

	file, _ := obj.read_file("./examples/obj/test2.obj")	
	defer obj.destroy_file(&file)
	
	mesh := obj.get_mesh(&file)
	defer obj.destory_mesh(&mesh)
	
	cube_vertices = make([dynamic]Vertex)
	for index in mesh.indices {
		append(&cube_vertices, Vertex{mesh.positions[index], mesh.normals[index], mesh.texture_coordinates[index]})
	}

	aabb := core.aabb_from_positions(mesh.positions[:])
	origin := core.aabb_get_origin(aabb)
	camera.position = origin
	
	cube_indices  = make([dynamic]u32)
	for index in mesh.indices {
		append(&cube_indices, index)
	}
	
	vertex_buffer  = core.vk_vertex_buffer_create(vk.DeviceSize(size_of(Vertex) * len(cube_vertices)), &vk_allocator)
	index_buffer   = core.vk_index_buffer_create(vk.DeviceSize(size_of(u32) * len(cube_indices)), &vk_allocator)
	uniform_buffer = core.vk_uniform_buffer_create(size_of(ubo), &vk_allocator) 

	depth_format = .D32_SFLOAT
	create_depth_image(core.vk_swapchain_get_extent())
	
	core.vk_buffer_copy(transfer_pool, &vertex_buffer, raw_data(cube_vertices[:]), &vk_allocator)
	core.vk_buffer_copy(transfer_pool, &index_buffer, raw_data(cube_indices[:]), &vk_allocator)

	swapchain_format := core.vk_swapchain_get_image_format()
	rendering_info   := core.vk_rendering_info_create({swapchain_format}, depth_format) 

	binding_description, attribute_descriptions := core.vk_vertex_description_create(Vertex)
	defer delete(attribute_descriptions)
	
	vertex_input_state := core.vk_vertex_input_state_create({binding_description}, attribute_descriptions)

	vertex_module := core.vk_shader_module_create("shaders/obj.vert.spv")
	defer core.vk_shader_module_destroy(vertex_module)
	
	fragment_module := core.vk_shader_module_create("shaders/obj.frag.spv")
	defer core.vk_shader_module_destroy(fragment_module)
	
	color_blend_attachment_state := core.vk_color_blend_attachment_state_create()
	color_blend_state := core.vk_color_blend_state_create({color_blend_attachment_state})

	descriptor_pool = core.vk_descriptor_pool_create({.UNIFORM_BUFFER, .COMBINED_IMAGE_SAMPLER}, {Frames_In_Flight, Frames_In_Flight}, Frames_In_Flight)
	
	descriptor_layout = core.vk_descriptor_set_layout_create(
		{
			{
				binding         = 0,
				descriptorType  = .UNIFORM_BUFFER,
				descriptorCount = 1,
				stageFlags      = {.VERTEX, .FRAGMENT},
			},
			{
				binding         = 1,
				descriptorType  = .COMBINED_IMAGE_SAMPLER,
				descriptorCount = 1,
				stageFlags      = {.FRAGMENT}
			}
		},
	)

	descriptor_layouts: [Frames_In_Flight]vk.DescriptorSetLayout
	for i in 0..<Frames_In_Flight do descriptor_layouts[i] = descriptor_layout
	descriptor_sets = core.vk_descriptor_set_create(descriptor_pool, descriptor_layouts[:])

	input_assembly_state := core.vk_input_assembly_state_create()
	viewport_state       := core.vk_viewport_state_create()
	rasterizer_state     := core.vk_rasterizer_state_create()
	multisample_state    := core.vk_multisample_state_create()
	depth_stencil_state  := core.vk_depth_stencil_state_create()
	dynamic_state        := core.vk_dynamic_state_create()	
	
	pipeline, pipeline_layout = core.vk_graphics_pipeline_create(
		&rendering_info,
		&vertex_input_state,
		&input_assembly_state,
		&viewport_state,
		&rasterizer_state,
		&multisample_state,
		&depth_stencil_state,
		&color_blend_state,
		&dynamic_state,
		{
			core.vk_shader_stage_state_create({.VERTEX}, vertex_module, "main"),
			core.vk_shader_stage_state_create({.FRAGMENT}, fragment_module, "main"),
		},
		{descriptor_layout}
	)
}

application_run :: proc() {	
	using application

	dt: f64
	rotation: f32
	start, end: time.Tick
	frame, index: u32
	light_position: la.Vector3f32 = {2, -2, 2}
	light_color: la.Vector3f32 = {1, 0.3, 0.3}
	clicks: u32
	transform: core.Transform
	transform.scale = {1, 1, 1}
	transform.rotation = la.quaternion_from_pitch_yaw_roll_f32(0,0,0)
	core.transform_rotate(&transform, {1, 0, 0}, la.PI)
	
	for !core.window_should_close() {
		core.window_poll()		
		
		if core.input_is_key_pressed(.Key_Escape) do core.window_set_should_close(true)

		extent := core.vk_swapchain_get_extent()
		
		dt = time.duration_seconds(time.tick_diff(start, end))

		core.transform_rotate(&transform, {0, 1, 0}, f32(dt))
		
		start = time.tick_now()

		camera.speed = 2
		vecs := core.camera_3d_get_vectors(&camera)
		vecs[.Front] = vecs[.Right].zyx
		vecs[.Front].z *= -1
		if core.input_is_key_held(.Key_W) {
			camera.position += vecs[.Front] * f32(dt) * camera.speed
		}
		if core.input_is_key_held(.Key_S) {
			camera.position -= vecs[.Front] * f32(dt) * camera.speed
		}
		if core.input_is_key_held(.Key_D) {
			camera.position += vecs[.Right] * f32(dt) * camera.speed
		}
		if core.input_is_key_held(.Key_A) {
			camera.position -= vecs[.Right] * f32(dt) * camera.speed
		}
		if core.input_is_key_held(.Key_Space) {
			camera.position += {0, -1, 0} * f32(dt) * camera.speed
		}
		if core.input_is_key_held(.Key_Left_Shift) {
			camera.position += {0, 1, 0} * f32(dt) * camera.speed
		}
		if core.input_is_mouse_pressed(.Mouse_Button_Right) {
			clicks = (clicks + 1) % 4
			if clicks == 0 do light_color = {1, 0.3, 0.3}
			if clicks == 1 do light_color = {0.3, 1, 0.3}
			if clicks == 2 do light_color = {0.3, 0.3, 1}
			if clicks == 3 do light_color = {1, 1, 1}
		}
		if core.input_is_key_pressed(.Key_C) {
			core.camera_3d_set_fovy(&camera, la.to_radians(f32(20)))
		}
		if core.input_is_key_released(.Key_C) {
			core.camera_3d_set_fovy(&camera, la.to_radians(f32(60)))
		}
		if core.input_is_mouse_pressed(.Mouse_Button_Left) do light_position = camera.position
		
		core.camera_3d_update(&camera, core.input_get_relative_mouse_pos_f32())
		
		ubo.proj = core.camera_3d_get_view_projection(&camera)
		ubo.model = core.transform_get_matrix(&transform)
		ubo.position = camera.position.xyzz
		ubo.light_position = light_position.xyzz
		ubo.light_color = light_color.xyzz
		core.vk_buffer_copy(&uniform_buffer, &ubo)
	
		frame = (frame + 1) % Frames_In_Flight
		index = core.vk_swapchain_get_next_image_index(image_available[frame], block_until[frame])		
	
		core.vk_command_buffer_reset(command_buffers[frame])
		core.vk_command_buffer_begin(command_buffers[frame])
				
		core.vk_command_image_barrier(
			command_buffer  = command_buffers[frame],
			image           = core.vk_swapchain_get_image(index),
			dst_access_mask = {.COLOR_ATTACHMENT_WRITE},
			old_layout      = .UNDEFINED,
			new_layout      = .COLOR_ATTACHMENT_OPTIMAL,
			src_stage_mask  = {.TOP_OF_PIPE},
			dst_stage_mask  = {.COLOR_ATTACHMENT_OUTPUT},
		)	

		core.vk_command_image_barrier(
			command_buffers[frame],
			image             = &depth_image,
			dst_access_mask   = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
			old_layout        = .UNDEFINED,
			new_layout        = .DEPTH_ATTACHMENT_OPTIMAL,
			src_stage_mask    = {.TOP_OF_PIPE},
			dst_stage_mask    = {.EARLY_FRAGMENT_TESTS},
			subresource_range = {{.DEPTH}, 0, 1, 0, 1}
		)
		
		depth_attachment := core.vk_depth_attachment_create(depth_image.view)
		
		core.vk_command_begin_rendering(
			command_buffer = command_buffers[frame],
			render_area = {
				offset = {0, 0},
				extent = extent
			},
			color_attachments = {
				core.vk_color_attachment_create(core.vk_swapchain_get_image_view(index))
			},
			depth_attachment = &depth_attachment
		)
		
		core.vk_command_viewport_set(
			command_buffers[frame],
			{{
				x        = 0,
				y        = 0,
				width    = f32(extent.width),
				height   = f32(extent.height),
				minDepth = 0,
				maxDepth = 1,
			}}
		)

		core.vk_command_scissor_set(
			command_buffers[frame],
			{{
				offset = {0, 0},
				extent = extent
			}}
		)
		
		core.vk_command_graphics_pipeline_bind(command_buffers[frame], pipeline)
		core.vk_command_descriptor_set_bind(command_buffers[frame], pipeline_layout, .GRAPHICS, descriptor_sets[frame])
		core.vk_descriptor_set_update_uniform_buffer(descriptor_sets[frame], 0, &uniform_buffer)
		core.vk_descriptor_set_update_image(descriptor_sets[frame], 1, &image, sampler)
		core.vk_command_vertex_buffers_bind(command_buffers[frame], {vertex_buffer.handle})
		core.vk_command_index_buffer_bind(command_buffers[frame], index_buffer.handle, .UINT32)
		core.vk_command_draw_indexed(command_buffers[frame], u32(len(cube_indices)))
		core.vk_command_end_rendering(command_buffers[frame])
		
		core.vk_command_image_barrier(
			command_buffer  = command_buffers[frame],
			image           = core.vk_swapchain_get_image(index),
			src_stage_mask  = {.COLOR_ATTACHMENT_OUTPUT},
			dst_stage_mask  = {.BOTTOM_OF_PIPE},
			src_access_mask = {.COLOR_ATTACHMENT_WRITE},
			old_layout      = .COLOR_ATTACHMENT_OPTIMAL,
			new_layout      = .PRESENT_SRC_KHR,			
		)
		
		core.vk_command_buffer_end(command_buffers[frame])

		core.vk_queue_submit(
			command_buffers[frame],
			render_finished[index],
			image_available[frame],
			{.COLOR_ATTACHMENT_OUTPUT},
			block_until[frame]
		)

		core.vk_present(render_finished[index], index)		
		
		end = time.tick_now()
	}	
	
	delete(cube_vertices)
	delete(cube_indices)
	core.vk_sampler_destroy(sampler)
	core.vk_image_destroy(&image)
	core.vk_image_destroy(&depth_image)
	core.vk_command_buffer_destroy(command_buffers)
	core.vk_command_pool_destroy(graphics_pool)
	core.vk_command_pool_destroy(transfer_pool)
	core.vk_semaphore_destroy(image_available)
	core.vk_semaphore_destroy(render_finished)
	core.vk_fence_destroy(block_until)
	core.vk_buffer_destroy(&vertex_buffer)
	core.vk_buffer_destroy(&index_buffer)
	core.vk_buffer_destroy(&uniform_buffer)
	core.vk_descriptor_set_layout_destroy(descriptor_layout)
	core.vk_descriptor_set_destroy(descriptor_pool, descriptor_sets)
	core.vk_descriptor_pool_destroy(descriptor_pool)
	core.vk_graphics_pipeline_destroy(pipeline, pipeline_layout)
	core.window_destroy()
}


main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)
	
	application_create()
	application_run()
}

