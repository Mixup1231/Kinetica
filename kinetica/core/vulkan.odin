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
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
	queue_flags:   vk.QueueFlags,
	type:          vk.PhysicalDeviceType,

	// NOTE(Mitchell): Added these if you ever wanted to use them
	supports_geometry_shader:     bool,
	supports_tessellation_shader: bool,
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
	
	// load process addresses
	context.user_ptr = &instance.handle
	get_proc_address :: proc(p: rawptr, name: cstring) {
		(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress((^vk.Instance)(context.user_ptr)^, name)
	}

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

	queues := make(map[vk.QueueFlag][2]u32)
	present_index: [2]u32 = {max(u32), max(u32)}

	found_suitable_device := false
	device_loop: for physical_device in physical_devices {
		// device properties
		device_properties: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(physical_device, &device_properties)
		
		if device_properties.deviceType != device_attributes.type do continue

		// device features
		device_features: vk.PhysicalDeviceFeatures
		vk.GetPhysicalDeviceFeatures(physical_device, &device_features)

		if device_attributes.supports_geometry_shader && !device_features.geometryShader do continue
		if device_attributes.supports_tessellation_shader && !device_features.tessellationShader do continue

		// device extensions
		device_extension_count: u32
		device_extensions:      []vk.ExtensionProperties
		vk_warn(vk.EnumerateDeviceExtensionProperties(physical_device, nil, &device_extension_count, nil))

		if device_extension_count == 0 && len(device_attributes.extensions) > 0 do continue

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
		// NOTE(Mitchell):
		// We always assume you will want to present, this could be bad if you want to run in a headless mode.
		// Consider adding device_attributes.can_present filter.
		present_mode_count: u32
		present_modes:      []vk.PresentModeKHR
		vk_warn(vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, vk_context.surface.handle, &present_mode_count, nil))

		if present_mode_count == 0 do continue

		present_modes = make([]vk.PresentModeKHR, present_mode_count)
		defer delete(present_modes)

		vk_warn(vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, vk_context.surface.handle, &present_mode_count, raw_data(present_modes)))
		for requested_present_mode in device_attributes.present_modes {
			supports_requested_present_mode: bool

			for supported_present_mode in present_modes {
				if requested_present_mode == supported_present_mode {
					supports_requested_present_mode = true
					break
				}
			}

			if !supports_requested_present_mode do continue device_loop
		}

		// formats
		format_count: u32
		formats:      []vk.SurfaceFormatKHR
		vk_warn(vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, vk_context.surface.handle, &format_count, nil))

		formats = make([]vk.SurfaceFormatKHR, format_count)
		defer delete(formats)

		vk_warn(vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, vk_context.surface.handle, &format_count, raw_data(formats)))
		for requested_format in device_attributes.formats {
			supports_requested_format: bool

			for supported_format in formats {
				if requested_format == supported_format {
					supports_requested_format = true
					break
				}
			}

			if !supports_requested_format do continue device_loop
		}

		queue_family_count: u32
		queue_families:     []vk.QueueFamilyProperties
		vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, nil)

		queue_families = make([]vk.QueueFamilyProperties, queue_family_count)
		defer delete(queue_families)

		vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, raw_data(queue_families))
		
		for &queue_index in vk_context.device.queue_indices {
			queue_index = max(u32)
		}

		index_count: u32
		for family, i in queue_families {
			for queue in device_attributes.queue_flags {
				if queue in family.queueFlags && queue not_in queues {
					queues[queue] = {u32(i), index_count}
					index_count += 1
				} else if queue in family.queueFlags && queue in queues {
					stored_family := &queues[queue]

					if index_count < stored_family[1] {
						stored_family[0] = u32(i)
						stored_family[1] = index_count
						index_count += 1
					}
				}

				supports_present: b32
				vk_warn(vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, u32(i), vk_context.surface.handle, &supports_present))
				if supports_present {
					if present_index[1] > index_count {
						present_index[0] = u32(i)
						present_index[1] = index_count
						index_count += 1
					}
				}
			}
			index_count = 0
		}

		//TODO(Mitchell): Make sure to check that the queues found match the requested queue types 
		found_suitable_device = true
		vk_context.device.physical = physical_device
		
		for queue in queues {
			#partial switch queue {
			case .GRAPHICS:
				vk_context.device.queue_indices[.Graphics] = queues[queue][0]
			case .COMPUTE:
				vk_context.device.queue_indices[.Compute]  = queues[queue][0]
			case .TRANSFER:
				vk_context.device.queue_indices[.Transfer] = queues[queue][0]
			}
		}
		vk_context.device.queue_indices[.Present] = present_index[0]

		log.info("Vulkan - Physical Device: Successfully found suitable physical device")
		break
	}
	ensure(found_suitable_device)


	/*---------------------------*/
	/* INITIALISE LOGICAL DEVICE */
	/*---------------------------*/
	unique_queue_indices := make(map[u32]u32)
	defer delete(unique_queue_indices)

	// NOTE(Mitchell): We need to know the set of queue indices and the count of queues for each of those indices
	for index, _ in vk_context.device.queue_indices {
		if index == max(u32) do continue                                            // not supported
		if index in unique_queue_indices do (&unique_queue_indices[index])^ += 1    // in set already, increment count
		if index not_in unique_queue_indices do unique_queue_indices[index] = index // not in set, insert
	}

	queue_create_infos := make([]vk.DeviceQueueCreateInfo, len(unique_queue_indices))
	defer delete(queue_create_infos)

	i: i32
	priority: f32 = 1
	for index, count in unique_queue_indices {
		queue_create_info: vk.DeviceQueueCreateInfo = {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = index,
			queueCount       = count,
			pQueuePriorities = &priority,
		}

		queue_create_infos[i] = queue_create_info
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
