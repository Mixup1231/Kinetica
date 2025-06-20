package core

import "core:log"
import "core:mem"

import "vendor:glfw"
import vk "vendor:vulkan"

VK_Queue_Type :: enum {
	Graphics,
	Compute,
	Transfer,
	Present,
}

VK_Instance :: struct {
	handle:     vk.Instance,
	extensions: []cstring,
	layers:     []cstring,
	app_info:   vk.ApplicationInfo,
}

VK_Device :: struct {
	logical:       vk.Device,
	physical:      vk.PhysicalDevice,
	queue_indices: [VK_Queue_Type]u32,
	queues:        [VK_Queue_Type]vk.Queue,
}

VK_Swapchain_Attributes :: struct {
	format:       vk.SurfaceFormatKHR,
	present_mode: vk.PresentModeKHR,
	extent:       vk.Extent2D,
	image_usage:  vk.ImageUsageFlags,
}

VK_Swapchain_Support_Details :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}

VK_Swapchain :: struct {
	handle:          vk.SwapchainKHR,
	images:          []vk.Image,
	image_views:     []vk.ImageView,
	attributes:      VK_Swapchain_Attributes,
	support_details: VK_Swapchain_Support_Details,
}

VK_Context :: struct {
	instance:  VK_Instance,
	surface:   vk.SurfaceKHR,
	device:    VK_Device,
	swapchain: VK_Swapchain,
	allocator: mem.Allocator,

	initialised: bool,
}

@(private)
vk_context: VK_Context

vulkan_init :: proc(
	allocator := context.allocator
) {
	context.allocator = allocator
	ensure(!vk_context.initialised)

	instance := &vk_context.instance
	
	// load process addresses
	context.user_ptr = &instance.handle
	get_proc_address :: proc(p: rawptr, name: cstring) {
		(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress((^vk.Instance)(context.user_ptr)^, name)
	}
	 
	// initialise instance
	// NOTE(Mitchell): I was unsure how we wanted to handle the other variables, so I've only filled in this
	instance.app_info = {
		sType         = .APPLICATION_INFO,
		pEngineName   = "Kinetica",
		engineVersion = vk.MAKE_VERSION(1, 0, 0),
	}
}
