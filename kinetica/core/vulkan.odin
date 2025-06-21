package core

import "core:os"
import "core:log"
import "core:mem"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

// TODO(Mitchell): Implement Vulkan debug logging (callback)

VK_Queue_Type :: enum {
	Graphics,
	Compute,
	Transfer,
	Present,
}
VK_Queues :: distinct bit_set[VK_Queue_Type]

VK_Instance :: struct {
	handle:     vk.Instance,
	extensions: []cstring,
	layers:     []cstring,
	app_info:   vk.ApplicationInfo,
}

// NOTE(Mitchell): This was created for api naming consistency (vk_context.surface.handle)
VK_Surface :: struct {
	handle: vk.SurfaceKHR
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
	surface:   VK_Surface,
	device:    VK_Device,
	swapchain: VK_Swapchain,
	allocator: mem.Allocator,

	initialised: bool,
}

VK_Application_Info :: struct {
	api_version: u32,
	app_name:    cstring,
	app_version: u32,
	extensions:  []cstring,
	layers:      []cstring,
	features:    ^vk.ValidationFeaturesEXT,
}

// NOTE(Mitchell): This is used for filtering suitable physical devices
VK_Device_Attributes :: struct {
	extensions:    []cstring,
	present_modes: []vk.PresentModeKHR,
}

@(private)
vk_context: VK_Context

// NOTE(Mitchell): whats a SOLID? Feel free to pull these out into separate functions.
vulkan_init :: proc(
	app_info:          VK_Application_Info,
	device_attributes: VK_Device_Attributes,
	allocator := context.allocator
) {
	context.allocator = allocator
	ensure(window.initialised)
	ensure(!vk_context.initialised)

	instance := &vk_context.instance

	log.info("Vulkan - Initialising:")
	
	// load process addresses
	context.user_ptr = &instance.handle
	get_proc_address :: proc(p: rawptr, name: cstring) {
		(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress((^vk.Instance)(context.user_ptr)^, name)
	}
	vk.load_proc_addresses(get_proc_address)

	log.info("Vulkan - Functions: Successfully loaded instance functions")

	/*---------------------*/
	/* INITIALISE INSTANCE */	 
	/*---------------------*/
	// NOTE(Mitchell): I was unsure how we wanted to handle the other variables, so I've only filled in this
	instance.app_info = {
		sType              = .APPLICATION_INFO,
		pEngineName        = "Kinetica",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		pApplicationName   = app_info.app_name,
		applicationVersion = app_info.app_version,
		apiVersion         = app_info.api_version,
	}

	// NOTE(Mitchell):
	// Glfw has its own required extensions that must be appended to user requested extensions.
	// It may be worth checking for overlapping extension requests but for now I won't. 
	glfw_extensions := glfw.GetRequiredInstanceExtensions()
	extensions := make([]cstring, len(glfw_extensions) + len(app_info.extensions))
	copy(extensions[:len(glfw_extensions)], glfw_extensions)
	copy(extensions[len(glfw_extensions):], app_info.extensions)

	instance_create_info: vk.InstanceCreateInfo = {
		sType                   = .INSTANCE_CREATE_INFO,
		pNext                   = app_info.features,
		pApplicationInfo        = &instance.app_info,
		enabledLayerCount       = u32(len(app_info.layers)),
		ppEnabledLayerNames     = raw_data(app_info.layers),
		enabledExtensionCount   = u32(len(extensions)),
		ppEnabledExtensionNames = raw_data(extensions),
	}

	vk_fatal(vk.CreateInstance(&instance_create_info, nil, &vk_context.instance.handle))

	vk_context.instance.app_info   = instance.app_info
	vk_context.instance.extensions = app_info.extensions
	vk_context.instance.layers     = app_info.layers

	log.info("Vulkan: Successfully created Vulkan Instance")
	log.info("Vulkan - Layers:", app_info.layers)
	log.info("Vulkan - Extensions:", extensions)
	
	/*--------------------*/
	/* INITIALISE SURFACE */
	/*--------------------*/
	vk_fatal(glfw.CreateWindowSurface(vk_context.instance.handle, window.handle, nil, &vk_context.surface.handle))

	log.info("Vulkan: Successfully created Vulkan Surface")

	/*----------------------------*/
	/* INITIALISE PHYSICAL DEVICE */
	/*----------------------------*/
	physical_device_count: u32
	physical_devices:      []vk.PhysicalDevice
	vk_fatal(vk.EnumeratePhysicalDevices(vk_context.instance.handle, &physical_device_count, nil))
	
	physical_devices = make([]vk.PhysicalDevice, physical_device_count)
	defer delete(physical_devices)
	
	vk_fatal(vk.EnumeratePhysicalDevices(vk_context.instance.handle, &physical_device_count, raw_data(physical_devices)))
		
	queues_found := make(map[vk.QueueFlag][2]u32)
	defer delete(queues_found)

	best_physical_device: vk.PhysicalDevice
	device_loop: for physical_device in physical_devices {
		// type
		device_properties: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(physical_device, &device_properties)
		if device_properties.deviceType != .DISCRETE_GPU do continue

		// extensions
		device_extension_count: u32
		device_extensions:      []vk.ExtensionProperties
		vk_warn(vk.EnumerateDeviceExtensionProperties(physical_device, nil, &device_extension_count, nil))

		device_extensions = make([]vk.ExtensionProperties, device_extension_count)
		defer delete(device_extensions)
		
		vk_warn(vk.EnumerateDeviceExtensionProperties(physical_device, nil, &device_extension_count, raw_data(device_extensions)))
		for requested_extension in device_attributes.extensions {
			supports_requested_extension: bool
			
			for &supported_extension in device_extensions {
				if requested_extension == cstring(&supported_extension.extensionName[0]) {
					supports_requested_extension = true
					break
				}
			}

			if !supports_requested_extension do continue device_loop
		}

		// present modes
		present_mode_count: u32
		present_modes:      []vk.PresentModeKHR
		vk_warn(vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, vk_context.surface.handle, &present_mode_count, nil))

		present_modes = make([]vk.PresentModeKHR, present_mode_count)
		defer delete(present_modes)

		vk_warn(vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, vk_context.surface.handle, &present_mode_count, raw_data(present_modes)))
		for requested_present_mode in device_attributes.present_modes {
			supports_present_mode: bool

			for supported_present_mode in present_modes {
				if requested_present_mode == supported_present_mode {
					supports_present_mode = true
					break
				}
			}

			if !supports_present_mode do continue device_loop
		}
		
		// queues
		present_index:     [2]u32 = {max(u32), max(u32)}
		queue_index_count: u32
	
		queue_family_count: u32
		queue_families:     []vk.QueueFamilyProperties
		vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, nil)

		queue_families = make([]vk.QueueFamilyProperties, queue_family_count)
		defer delete(queue_families)

		vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, raw_data(queue_families))
		required_queues : vk.QueueFlags : {.GRAPHICS, .COMPUTE, .TRANSFER}
		
		for family, i in queue_families {
			for queue in required_queues {
				if queue in family.queueFlags && queue not_in queues_found {
					queues_found[queue] = {u32(i), queue_index_count}
					queue_index_count += 1
				} else if queue in family.queueFlags && queue in queues_found {
					stored_family := &queues_found[queue]
					if queue_index_count < stored_family[1] {
						stored_family[0] = u32(i)
						stored_family[1] = queue_index_count
						queue_index_count += 1
					}
				} 

				can_present: b32
				vk_warn(vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, u32(i), vk_context.surface.handle, &can_present))
				if can_present && queue_index_count < present_index[1] {
					present_index[0] = u32(i)
					present_index[1] = queue_index_count
					queue_index_count += 1
				}
			}
			
			queue_index_count = 0
			clear(&queues_found)
		}

		// NOTE(Mitchell): 3 = (graphics, compute, and transfer)
		if len(queues_found) != 3 && present_index[0] == max(u32) do continue

		for queue, index_count_pair in queues_found {
			#partial switch(queue) {
			case .GRAPHICS: vk_context.device.queue_indices[.Graphics] = index_count_pair[0]
			case .COMPUTE:  vk_context.device.queue_indices[.Compute]  = index_count_pair[0]
			case .TRANSFER: vk_context.device.queue_indices[.Transfer] = index_count_pair[0]
			}
		}
		
		best_physical_device = physical_device
		break
	}
	ensure(best_physical_device != nil)

	vk_context.device.physical = best_physical_device

	log.info("Vulkan - Physical Device: Successfully found physical device")
	
	/*---------------------------*/
	/* INITIALISE LOGICAL DEVICE */
	/*---------------------------*/
	unique_queue_indices := make(map[u32]u32)
	defer delete(unique_queue_indices)

	// NOTE(Mitchell): We need to know the set of queue indices and the count of queues for each of those indices
	for index, _ in vk_context.device.queue_indices {
		if index in unique_queue_indices do (&unique_queue_indices[index])^ += 1    // in set already, increment count
		if index not_in unique_queue_indices do unique_queue_indices[index] = 1     // not in set, insert
	}

	queue_create_infos := make([]vk.DeviceQueueCreateInfo, len(unique_queue_indices))
	defer delete(queue_create_infos)

	i := 0
	priority: f32 = 1
	for index, count in unique_queue_indices {
		queue_create_infos[i] = {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = index,
			queueCount       = count,
			pQueuePriorities = &priority,
		}
		i += 1
	}

	device_create_info: vk.DeviceCreateInfo = {
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = u32(len(unique_queue_indices)),
		pQueueCreateInfos       = raw_data(queue_create_infos),
		enabledExtensionCount   = u32(len(device_attributes.extensions)),
		ppEnabledExtensionNames = raw_data(device_attributes.extensions) if len(device_attributes.extensions) > 0 else nil,
		enabledLayerCount       = u32(len(vk_context.instance.layers)),
		ppEnabledLayerNames     = raw_data(vk_context.instance.layers) 
	}
	
	vk_fatal(vk.CreateDevice(vk_context.device.physical, &device_create_info, nil, &vk_context.device.logical))
	for index, queue in vk_context.device.queue_indices {
		if index != max(u32) {
			stored_index := &unique_queue_indices[index]
			vk.GetDeviceQueue(vk_context.device.logical, index, stored_index^-1, &vk_context.device.queues[queue])
			stored_index^ -= 1

			log.info("Vulkan - Queue: Successfully retrieved queue")
		}
	}

	vk.load_proc_addresses_device(vk_context.device.logical)
	
	log.info("Vulkan - Logical Device: Successfully created logical device")
}

// NOTE(Mitchell): This is a temporary solution for Vulkan error checking, feel free to change it.
vk_fatal :: #force_inline proc(result: vk.Result, location := #caller_location, msg: ..cstring) {
	if result != .SUCCESS {
		log.fatalf("%s Vulkan - Fatal %v: %s", location, result, msg)
		os.exit(-1)
	}
} 

// NOTE(Mitchell): This is a temporary solution for Vulkan error checking, feel free to change it.
vk_warn :: #force_inline proc(result: vk.Result, location := #caller_location, msg: ..cstring) {
	if result != .SUCCESS {
		log.warnf("%s Vulkan - Warn %v: %s", location, result, msg)
	}
} 
