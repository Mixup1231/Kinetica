package engine

import "../../../kinetica/core"

import vk "vendor:vulkan"

Renderer :: struct {
	vk_allocator:      core.VK_Allocator,
	depth_format:      vk.Format,
	depth_image:       core.VK_Image,
	graphics_pool:     core.VK_Command_Pool,
	transfer_pool:     core.VK_Command_Pool,
	command_buffers:   []core.VK_Command_Buffer,
	image_available:   []vk.Semaphore,
	render_finished:   []vk.Semaphore,
	block_until:       []vk.Fence,
	descriptor_pool:   vk.DescriptorPool,
	descriptor_layout: vk.DescriptorSetLayout,
	descriptor_sets:   []vk.DescriptorSet,
	pipeline:          vk.Pipeline,
	pipeline_layout:   vk.PipelineLayout,

	initialised: bool,
}

@(private="file")
renderer: Renderer

renderer_init :: proc() {
	using renderer 
	ensure(!initialised)
	
	vk_allocator  = core.vk_allocator_get_default()
	transfer_pool = core.vk_command_pool_create(.Transfer)
	
	graphics_pool   = core.vk_command_pool_create(.Graphics)
	command_buffers = core.vk_command_buffer_create(graphics_pool, .PRIMARY, Frames_In_Flight)
	
	image_available = core.vk_semaphore_create(Frames_In_Flight)
	block_until     = core.vk_fence_create(true, Frames_In_Flight)
	
	swapchain_image_count := core.vk_swapchain_get_image_count()
	render_finished = core.vk_semaphore_create(swapchain_image_count)
	
	depth_format = .D32_SFLOAT
	recreate_depth_image(core.vk_swapchain_get_extent())
	core.vk_swapchain_set_recreation_callback(recreate_depth_image)

	swapchain_format := core.vk_swapchain_get_image_format()
	rendering_info   := core.vk_rendering_info_create({swapchain_format}, depth_format)

	initialised = true
}

renderer_destroy :: proc() {
	using renderer
	ensure(initialised)

	initialised = false
}

renderer_render_scene :: proc(
	scene: ^Scene
) {
	using renderer
	assert(scene != nil)
}

@(private="file")
recreate_depth_image :: proc(
	extent: vk.Extent2D
) {
	using renderer

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
