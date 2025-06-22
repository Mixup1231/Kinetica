package core

import "core:os"
import "core:log"
import "core:mem"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

// TODO(Mitchell):
// Implement Vulkan debug logging (callback)
// Caching valid physical devices
// Code formatting
// Testing

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

	initialised: bool,
}

VK_Surface :: struct {
	handle: vk.SurfaceKHR
}

VK_Device_Attributes :: struct {
	extensions:    []cstring,
	features:      rawptr,
	present_modes: []vk.PresentModeKHR,
}

VK_Device :: struct {
	logical:       vk.Device,
	physical:      vk.PhysicalDevice,
	queue_indices: [VK_Queue_Type]u32,
	queues:        [VK_Queue_Type]vk.Queue,

	initialised: bool,
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

	initialised: bool,
}

VK_Swapchain :: struct {
	handle:          vk.SwapchainKHR,
	images:          []vk.Image,
	image_views:     []vk.ImageView,
	attributes:      VK_Swapchain_Attributes,
	support_details: VK_Swapchain_Support_Details,

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

VK_Context :: struct {
	instance:  VK_Instance,
	surface:   VK_Surface,
	device:    VK_Device,
	swapchain: VK_Swapchain,

	initialised: bool,
}

@(private)
vk_context: VK_Context

vulkan_init :: proc(
	app_info:             VK_Application_Info,
	device_attributes:    VK_Device_Attributes,
	swapchain_attributes: VK_Swapchain_Attributes,
	allocator := context.allocator
) {
	context.allocator = allocator
	ensure(window.initialised)
	ensure(!vk_context.initialised)

	device_attributes    := device_attributes
	swapchain_attributes := swapchain_attributes
	instance             := &vk_context.instance

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
	vk_context.initialised         = true

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
	physical_devices: []vk.PhysicalDevice
	vk_fatal(vk.EnumeratePhysicalDevices(vk_context.instance.handle, &physical_device_count, nil))
	ensure(physical_device_count != 0)
	
	physical_devices = make([]vk.PhysicalDevice, physical_device_count)
	defer delete(physical_devices)
	
	vk_fatal(vk.EnumeratePhysicalDevices(vk_context.instance.handle, &physical_device_count, raw_data(physical_devices)))		

	best_rating: u64	
	for physical_device in physical_devices {
		valid, rating, queue_indices := vulkan_rate_physical_device(physical_device, &device_attributes)
		if valid && rating > best_rating {
			best_rating = rating
			vk_context.device.physical      = physical_device
			vk_context.device.queue_indices = queue_indices
		}
	}
	ensure(vk_context.device.physical != nil)

	log.info("Vulkan - Physical Device: Successfully found physical device")
	
	/*---------------------------*/
	/* INITIALISE LOGICAL DEVICE */
	/*---------------------------*/
	unique_queue_indices := make(map[u32]u32)
	defer delete(unique_queue_indices)

	// NOTE(Mitchell): We need to know the set of queue indices and the count of queues for each of those indices
	for index, _ in vk_context.device.queue_indices {
		if index in unique_queue_indices do (&unique_queue_indices[index])^ += 1 // in set already, increment count
		if index not_in unique_queue_indices do unique_queue_indices[index] = 1  // not in set, insert
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
			pQueuePriorities = &priority
		}
		i += 1
	}

	device_create_info: vk.DeviceCreateInfo = {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = device_attributes.features,
		queueCreateInfoCount    = u32(len(unique_queue_indices)),
		pQueueCreateInfos       = raw_data(queue_create_infos),
		enabledExtensionCount   = u32(len(device_attributes.extensions)),
		ppEnabledExtensionNames = raw_data(device_attributes.extensions),
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
	vk_context.device.initialised = true
	
	log.info("Vulkan: Successfully created logical device")

	/*----------------------*/
	/* INITIALISE SWAPCHAIN */
	/*----------------------*/
	vulkan_create_swapchain(&swapchain_attributes)
}

vulkan_destroy :: proc() {
	ensure(vk_context.initialised)
	ensure(vk_context.instance.initialised)
	ensure(vk_context.device.initialised)
	ensure(vk_context.swapchain.initialised)

	vk.QueueWaitIdle(vk_context.device.queues[.Graphics])
	vk_context.initialised = false

	// swapchain
	vk_context.device.initialised = false
	vk.DestroySwapchainKHR(vk_context.device.logical, vk_context.swapchain.handle, nil)
	for image_view in vk_context.swapchain.image_views {
		vk.DestroyImageView(vk_context.device.logical, image_view, nil)
	}
	delete(vk_context.swapchain.images)
	delete(vk_context.swapchain.image_views)

	// device
	vk_context.device.initialised = false
	vk.DestroyDevice(vk_context.device.logical, nil)

	// surface
	vk.DestroySurfaceKHR(vk_context.instance.handle, vk_context.surface.handle, nil)

	// instance
	vk_context.instance.initialised = false
	vk.DestroyInstance(vk_context.instance.handle, nil)
}

@(private="file")
vulkan_rate_physical_device :: proc(
	physical_device:   vk.PhysicalDevice,
	device_attributes: ^VK_Device_Attributes,
	allocator := context.allocator
) -> (
	valid:         bool,
	rating:        u64,
	queue_indices: [VK_Queue_Type]u32,
) {
	context.allocator = allocator
	ensure(device_attributes != nil)

	/*--------------*/
	/* REQUIREMENTS */	
	/*--------------*/
	// extensions
	device_extension_count: u32
	device_extensions: []vk.ExtensionProperties
	vk_warn(vk.EnumerateDeviceExtensionProperties(physical_device, nil, &device_extension_count, nil))
	if device_extension_count == 0 do return false, 0, {}

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
		if !supports_requested_extension do return false, 0, {}
	}

	// present modes
	present_mode_count: u32
	present_modes: []vk.PresentModeKHR
	vk_warn(vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, vk_context.surface.handle, &present_mode_count, nil))
	if present_mode_count == 0 do return false, 0, {}

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
		if !supports_present_mode do return false, 0, {}
	}	
	
	// queues
	queues_found := make(map[vk.QueueFlag][2]u32)
	defer delete(queues_found)
	
	required_queues : vk.QueueFlags : {.GRAPHICS, .COMPUTE, .TRANSFER}
	present_index: [2]u32 = {max(u32), max(u32)}
	queue_index_count: u32
	
	queue_family_count: u32
	queue_families: []vk.QueueFamilyProperties
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, nil)
	if queue_family_count == 0 do return false, 0, {}

	queue_families = make([]vk.QueueFamilyProperties, queue_family_count)
	defer delete(queue_families)

	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, raw_data(queue_families))
	for family, i in queue_families {
		queue_index_count = 0
		
		for queue in required_queues {
			if queue in family.queueFlags && queue in queues_found {
				stored_family := &queues_found[queue]
				if queue_index_count < stored_family[1] {
					stored_family[0] = u32(i)
					stored_family[1] = queue_index_count
					queue_index_count += 1
				}
			} 	
			if queue in family.queueFlags && queue not_in queues_found {
				queues_found[queue] = {u32(i), queue_index_count}
				queue_index_count += 1
			}

			can_present: b32
			vk_warn(vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, u32(i), vk_context.surface.handle, &can_present))
			if can_present && queue_index_count < present_index[1] {
				present_index[0] = u32(i)
				present_index[1] = queue_index_count
				queue_index_count += 1
			}
		}		
	}

	// failed to find required queues
	if .GRAPHICS not_in queues_found || .COMPUTE not_in queues_found || .TRANSFER not_in queues_found do return false, 0, {}

	queue_indices[.Graphics] = queues_found[.GRAPHICS][0]
	queue_indices[.Compute]  = queues_found[.COMPUTE][0]
	queue_indices[.Transfer] = queues_found[.TRANSFER][0]	

	/*--------*/
	/* RATING */	
	/*--------*/
	device_properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(physical_device, &device_properties)	
	
	device_features: vk.PhysicalDeviceFeatures
	vk.GetPhysicalDeviceFeatures(physical_device, &device_features)

	// NOTE(Mitchell): We may want to play around with these numbers
	rating += u64(device_properties.limits.maxImageDimension2D)
	rating += u64(device_properties.limits.maxUniformBufferRange / 1024)
	rating += u64(device_properties.limits.maxStorageBufferRange / 1024)
	rating += u64(device_properties.limits.maxComputeSharedMemorySize / 512)
	rating += u64(device_properties.limits.maxFramebufferWidth / 64)
	rating += u64(device_properties.limits.maxFramebufferHeight / 64)
	
	if device_properties.deviceType == .DISCRETE_GPU do rating += 1000
	if device_features.samplerAnisotropy do rating += 1000
	if device_features.geometryShader do rating += 100
	if device_features.tessellationShader do rating += 100

	return true, rating, queue_indices
}

// NOTE(Mitchell): Uses vk_context.device.physical and vk_context.surface.handle to retrieve information
@(private="file")
vulkan_query_swapchain_support :: proc(
	allocator := context.allocator
) -> (
	support_details: VK_Swapchain_Support_Details
) {
	context.allocator = allocator
	ensure(!vk_context.swapchain.support_details.initialised)

	vk_fatal(vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(vk_context.device.physical, vk_context.surface.handle, &support_details.capabilities))

	format_count: u32
	vk_fatal(vk.GetPhysicalDeviceSurfaceFormatsKHR(vk_context.device.physical, vk_context.surface.handle, &format_count, nil))
	ensure(format_count != 0)

	support_details.formats = make([]vk.SurfaceFormatKHR, format_count)
	vk_fatal(vk.GetPhysicalDeviceSurfaceFormatsKHR(vk_context.device.physical, vk_context.surface.handle, &format_count, raw_data(support_details.formats)))

	present_mode_count: u32
	vk_fatal(vk.GetPhysicalDeviceSurfacePresentModesKHR(vk_context.device.physical, vk_context.surface.handle, &present_mode_count, nil))
	ensure(present_mode_count != 0)

	support_details.present_modes = make([]vk.PresentModeKHR, present_mode_count)
	vk_fatal(vk.GetPhysicalDeviceSurfacePresentModesKHR(vk_context.device.physical, vk_context.surface.handle, &present_mode_count, raw_data(support_details.present_modes)))

	support_details.initialised = true

	return support_details
}

// NOTE(Mitchell): This is a separate function because you need to recreate the swapchain on resize
@(private="file")
vulkan_create_swapchain :: proc(
	swapchain_attributes: ^VK_Swapchain_Attributes,
	allocator := context.allocator
) {
	context.allocator = allocator
	ensure(!vk_context.swapchain.initialised)
	ensure(swapchain_attributes != nil)

	vk_context.swapchain.attributes = swapchain_attributes^

	swapchain_create_info: vk.SwapchainCreateInfoKHR = {
		sType   = .SWAPCHAIN_CREATE_INFO_KHR,
		surface = vk_context.surface.handle
	}

	support_details := &vk_context.swapchain.support_details
	attributes      := &vk_context.swapchain.attributes

	if support_details.initialised {
		delete(support_details.formats)
		delete(support_details.present_modes)
	}
	
	support_details^ = vulkan_query_swapchain_support()

	if support_details.capabilities.currentExtent.width != max(u32) {
		swapchain_create_info.imageExtent = support_details.capabilities.currentExtent
		attributes.extent = swapchain_create_info.imageExtent
	} else {
		extent: vk.Extent2D = {
			width  = max(support_details.capabilities.minImageExtent.width, attributes.extent.width),
			height = max(support_details.capabilities.minImageExtent.height, attributes.extent.height),
		}
		swapchain_create_info.imageExtent = extent
		attributes.extent = extent
	}

	image_count := support_details.capabilities.minImageCount+1
	if support_details.capabilities.maxImageCount > 0 && image_count > support_details.capabilities.minImageCount {
		image_count = support_details.capabilities.maxImageCount
	}

	swapchain_create_info.imageArrayLayers = 1
	swapchain_create_info.minImageCount    = image_count
	swapchain_create_info.imageUsage       = attributes.image_usage

	queue_indices := &vk_context.device.queue_indices
	if queue_indices[.Graphics] == queue_indices[.Present] {
		swapchain_create_info.imageSharingMode = .EXCLUSIVE
	} else {
		indices: []u32 = { queue_indices[.Graphics], queue_indices[.Present] }
		swapchain_create_info.pQueueFamilyIndices   = raw_data(indices)
		swapchain_create_info.queueFamilyIndexCount = 2
		swapchain_create_info.imageSharingMode      = .CONCURRENT
	}

	swapchain_create_info.preTransform = support_details.capabilities.currentTransform
	swapchain_create_info.clipped      = true

	supports_requested_present_mode: bool
	for present_mode in support_details.present_modes {
		if present_mode == attributes.present_mode {
			swapchain_create_info.presentMode = present_mode
			supports_requested_present_mode = true
			break
		}
	}

	if !supports_requested_present_mode {
		swapchain_create_info.presentMode = .FIFO // always supported
		attributes.present_mode = .FIFO
	}

	supports_requested_format: bool
	for format in support_details.formats {
		if format == attributes.format {
			swapchain_create_info.imageFormat = format.format
			swapchain_create_info.imageColorSpace = format.colorSpace
			supports_requested_format = true
			break
		}
	}

	if !supports_requested_format {
		swapchain_create_info.imageFormat = support_details.formats[0].format
		swapchain_create_info.imageColorSpace = support_details.formats[0].colorSpace
		attributes.format = support_details.formats[0]
	}

	swapchain_create_info.compositeAlpha = {.OPAQUE}

	vk_fatal(vk.CreateSwapchainKHR(vk_context.device.logical, &swapchain_create_info, nil, &vk_context.swapchain.handle))

	log.info("Vulkan: Successfully create the swapchain")

	swapchain := &vk_context.swapchain
	if swapchain.images == nil {
		swapchain.images = make([]vk.Image, image_count)
	} else {
		ensure(u32(len(swapchain.images)) == image_count)
	}
	
	if swapchain.image_views == nil {
		swapchain.image_views = make([]vk.ImageView, image_count)
	} else {
		ensure(u32(len(swapchain.images)) == image_count)
	}

	vk_fatal(vk.GetSwapchainImagesKHR(vk_context.device.logical, swapchain.handle, &image_count, raw_data(swapchain.images)))
	for image, i in swapchain.images {
		image_view_create_info: vk.ImageViewCreateInfo = {
			sType            = .IMAGE_VIEW_CREATE_INFO,
			image            = image,
			viewType         = .D2,
			format           = attributes.format.format,
			subresourceRange = {
				aspectMask     = {.COLOR},
				baseMipLevel   = 0,
				levelCount     = 1,
				baseArrayLayer = 0,
				layerCount     = 1
			}
		}

		vk_fatal(vk.CreateImageView(vk_context.device.logical, &image_view_create_info, nil, &swapchain.image_views[i]))

		log.info("Vulkan: Successfully create swapchain image-view", i+1)
	}
}

vk_fatal :: #force_inline proc(result: vk.Result, msg: cstring = "", location := #caller_location) {
	if result != .SUCCESS {
		log.fatalf("%s Vulkan - Fatal %v: %s", location, result, msg)
		os.exit(-1)
	}
}

vk_warn :: #force_inline proc(result: vk.Result, msg: cstring = "", location := #caller_location) {
	if result != .SUCCESS {
		log.warnf("%s Vulkan - Warn %v: %s", location, result, msg)
	}
} 
