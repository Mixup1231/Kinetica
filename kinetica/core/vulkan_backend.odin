#+private
package core

import "core:os"
import "core:log"
import "core:mem"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

// TODO(Mitchell):
// Vulkan debug logging (callback)
// Caching valid physical devices 

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
	image_count:  u32
}

VK_Swapchain_Support_Details :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,

	initialised: bool,
}

VK_Swapchain :: struct {
	handle:          vk.SwapchainKHR,
	images:          []VK_Image,
	attributes:      VK_Swapchain_Attributes,
	support_details: VK_Swapchain_Support_Details,
	on_recreation:   [dynamic]proc(vk.Extent2D),

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
vk_context: VK_Context

vk_init :: proc(
	app_info:             VK_Application_Info,
	device_attributes:    VK_Device_Attributes,
	swapchain_attributes: VK_Swapchain_Attributes,
	allocator := context.allocator
) {	
	context.allocator = allocator
	ensure(glfw_context.initialised)
	ensure(!vk_context.initialised)

	device_attributes    := device_attributes
	swapchain_attributes := swapchain_attributes
	instance             := &vk_context.instance

	log.info("Vulkan: Initialising")
	
	// load process addresses
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	log.info("Vulkan: Successfully loaded instance proc address")

	// instance
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

	vk_context.instance.app_info    = instance.app_info
	vk_context.instance.extensions  = app_info.extensions
	vk_context.instance.layers      = app_info.layers
	vk_context.instance.initialised = true

	vk.load_proc_addresses_instance(vk_context.instance.handle)

	log.info("Vulkan: Successfully created Vulkan instance")
	log.info("Vulkan - Layers:", app_info.layers)
	log.info("Vulkan - Extensions:", extensions)

	// surface	
	vk_fatal(glfw.CreateWindowSurface(vk_context.instance.handle, glfw_context.handle, nil, &vk_context.surface.handle))

	log.info("Vulkan: Successfully created Vulkan Surface")

	// physical device
	physical_device_count: u32
	physical_devices: []vk.PhysicalDevice
	vk_fatal(vk.EnumeratePhysicalDevices(vk_context.instance.handle, &physical_device_count, nil))
	ensure(physical_device_count != 0)
	
	physical_devices = make([]vk.PhysicalDevice, physical_device_count)
	defer delete(physical_devices)
	
	vk_fatal(vk.EnumeratePhysicalDevices(vk_context.instance.handle, &physical_device_count, raw_data(physical_devices)))		

	best_rating: u32
	best_queue_indices: [VK_Queue_Type][2]u32
	for physical_device in physical_devices {
		valid, rating, queue_indices := vk_physical_device_rate(physical_device, &device_attributes)
		if valid && rating > best_rating {
			best_rating = rating
			vk_context.device.physical = physical_device
			for index_count, queue in queue_indices do vk_context.device.queue_indices[queue] = index_count[0]
			best_queue_indices = queue_indices
			continue
		}
	}
	ensure(vk_context.device.physical != nil)

	log.info("Vulkan: Successfully found physical device")

	// logical device
	largest_count: u32
	unique_queue_indices := make(map[u32]u32)
	defer delete(unique_queue_indices)

	// NOTE(Mitchell): We need to know the set of queue indices and the count of queues for each of those indices
	for index_count, queue in best_queue_indices {
		if index_count[0] not_in unique_queue_indices {
			unique_queue_indices[index_count[0]] = index_count[1]
			if index_count[1] > largest_count do largest_count = index_count[1]
		}
	}

	queue_create_infos := make([]vk.DeviceQueueCreateInfo, len(unique_queue_indices))
	defer delete(queue_create_infos)

	priorities := make([]f32, largest_count)
	for &priority in priorities do priority = 1
	defer delete(priorities)

	i := 0
	for index, count in unique_queue_indices {
		queue_create_infos[i] = {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = index,
			queueCount       = count,
			pQueuePriorities = raw_data(priorities)
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
	
	for index_count, queue in best_queue_indices {
		count := &unique_queue_indices[index_count[0]]
		vk.GetDeviceQueue(vk_context.device.logical, index_count[0], count^-1, &vk_context.device.queues[queue])
		if count^ > 1 do count^ -= 1
	}

	for queue, type in vk_context.device.queues do log.info("Vulkan - Queue:", type, "retrieved with index", vk_context.device.queue_indices[type])

	vk.load_proc_addresses_device(vk_context.device.logical)
	vk_context.device.initialised = true
	
	log.info("Vulkan: Successfully created logical device")

	// swapchain
	vk_swapchain_create(&swapchain_attributes)
	
	vk_context.initialised = true
}

vk_destroy :: proc() {
	ensure(vk_context.initialised)
	ensure(vk_context.instance.initialised)
	ensure(vk_context.device.initialised)
	ensure(vk_context.swapchain.initialised)

	vk.QueueWaitIdle(vk_context.device.queues[.Graphics])
	vk_context.initialised = false

	// swapchain
	vk_context.swapchain.initialised = false
	vk_context.swapchain.support_details.initialised = false
	vk.DestroySwapchainKHR(vk_context.device.logical, vk_context.swapchain.handle, nil)
	for &image in vk_context.swapchain.images do vk.DestroyImageView(vk_context.device.logical, image.view, nil)
	
	delete(vk_context.swapchain.images)
	delete(vk_context.swapchain.support_details.formats)
	delete(vk_context.swapchain.support_details.present_modes)
	delete(vk_context.swapchain.on_recreation)

	// device
	vk_context.device.initialised = false
	vk.DestroyDevice(vk_context.device.logical, nil)

	// surface
	vk.DestroySurfaceKHR(vk_context.instance.handle, vk_context.surface.handle, nil)

	// instance
	vk_context.instance.initialised = false
	vk.DestroyInstance(vk_context.instance.handle, nil)
}

vk_physical_device_rate :: proc(
	physical_device:   vk.PhysicalDevice,
	device_attributes: ^VK_Device_Attributes,
	allocator := context.allocator
) -> (
	valid:             bool,
	rating:            u32,
	queue_indices:     [VK_Queue_Type][2]u32,
) {
	context.allocator = allocator
	ensure(device_attributes != nil)

	// requirements
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
	present_index: [2]u32 = {max(u32), max(u32)}
	queues_found := make(map[vk.QueueFlag][3]u32)
	defer delete(queues_found)	
	
	queue_family_count: u32
	queue_families: []vk.QueueFamilyProperties
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, nil)
	if queue_family_count == 0 do return false, 0, {}
	
	queue_families = make([]vk.QueueFamilyProperties, queue_family_count)
	defer delete(queue_families)

	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, raw_data(queue_families))

	// find a graphics queue
	for family, i in queue_families {
		can_present: b32
		vk_warn(vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, u32(i), vk_context.surface.handle, &can_present))
		
		if .GRAPHICS in family.queueFlags && can_present {
			queues_found[.GRAPHICS] = {u32(i), 1, family.queueCount}
			present_index = {u32(i), 1}
			break
		} 
	}
	if .GRAPHICS not_in queues_found do return false, 0, {}

	// attempt to find dedicated transfer queue or a queue family that supports transfers and is not in use by graphics
	for family, i in queue_families {
		if .TRANSFER in family.queueFlags && .GRAPHICS not_in family.queueFlags && .COMPUTE not_in family.queueFlags {
			queues_found[.TRANSFER] = {u32(i), 1, family.queueCount}
			break
		} else if .TRANSFER in family.queueFlags && queues_found[.GRAPHICS][0] != u32(i) {
			queues_found[.TRANSFER] = {u32(i), 1, family.queueCount}
		}
	}

	// only family left to check is what the graphics queue is using
	if .TRANSFER not_in queues_found {
		family_info := &queues_found[.GRAPHICS]
		
		if .TRANSFER in queue_families[family_info[0]].queueFlags {
			// if family supports more than one queue, increment queue count
			if family_info[1] < family_info[2] do family_info[1] += 1
			queues_found[.TRANSFER] = family_info^
		} else {
			return false, 0, {}
		}
	}

	// attempt to find dedicated compute queue or queue family that is not in use by transfer
	decrement_graphics_queue_count: bool
	for family, i in queue_families {
		if .COMPUTE in family.queueFlags && .GRAPHICS not_in family.queueFlags && .TRANSFER not_in family.queueFlags {
			queues_found[.COMPUTE] = {u32(i), 1, family.queueCount}
			break
		} else if .COMPUTE in family.queueFlags && queues_found[.TRANSFER][0] != u32(i) {
			graphics_family_info := &queues_found[.GRAPHICS]

			// if graphics is using this family
			if graphics_family_info[0] == u32(i) {
				// try to create separate compute queue in family
				if graphics_family_info[2] > 1 do graphics_family_info[1] += 1
				queues_found[.COMPUTE] = graphics_family_info^
				decrement_graphics_queue_count = true
			} else {
				if decrement_graphics_queue_count {
					graphics_family_info[1] -= 1
					decrement_graphics_queue_count = false
				}
				queues_found[.COMPUTE] = {u32(i), 1, family.queueCount}
			}
		}
	}

	// only family left to check is what the trasnfer queue is using
	if .COMPUTE not_in queues_found {
		family_info := &queues_found[.TRANSFER]

		if .COMPUTE in queue_families[family_info[0]].queueFlags {
			// try to create separate compute queue in family
			if family_info[1] < family_info[2] do family_info[1] += 1
			queues_found[.COMPUTE] = family_info^
		} else {
			return false, 0, {}
		}
	}

	queue_indices[.Graphics] = queues_found[.GRAPHICS].xy
	queue_indices[.Compute]  = queues_found[.COMPUTE].xy
	queue_indices[.Transfer] = queues_found[.TRANSFER].xy
	queue_indices[.Present]  = present_index

	// rating
	device_properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(physical_device, &device_properties)	
	
	device_features: vk.PhysicalDeviceFeatures
	vk.GetPhysicalDeviceFeatures(physical_device, &device_features)

	// NOTE(Mitchell): We may want to play around with these numbers
	rating += device_properties.limits.maxImageDimension2D        / 1e4
	rating += device_properties.limits.maxUniformBufferRange      / 1e6
	rating += device_properties.limits.maxStorageBufferRange      / 1e9
	rating += device_properties.limits.maxComputeSharedMemorySize / 1e9
	
	if device_properties.deviceType == .DISCRETE_GPU do rating += 1e1
	if device_features.samplerAnisotropy  do rating += 1
	if device_features.geometryShader     do rating += 1
	if device_features.tessellationShader do rating += 1

	log.info("Vulken - Device:", transmute(cstring)raw_data(device_properties.deviceName[:]), "rating:", rating)

	return true, rating, queue_indices
}

// NOTE(Mitchell): Uses vk_context.device.physical and vk_context.surface.handle to retrieve information
vk_swapchain_query_support :: proc(
	allocator := context.allocator
) -> (
	support_details: VK_Swapchain_Support_Details
) {
	context.allocator = allocator
	ensure(vk_context.device.initialised)

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
vk_swapchain_create :: proc(
	swapchain_attributes: ^VK_Swapchain_Attributes,
	allocator := context.allocator
) {
	context.allocator = allocator
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
	
	support_details^ = vk_swapchain_query_support()

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
	if support_details.capabilities.maxImageCount > 0 && image_count > support_details.capabilities.maxImageCount {
		image_count = support_details.capabilities.maxImageCount
	}
	attributes.image_count = image_count

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

	log.info("Vulkan: Successfully created the swapchain")
	log.info("Vulkan - Swapchain Attributes:\n", vk_context.swapchain.attributes)

	swapchain := &vk_context.swapchain
	if swapchain.images == nil {
		swapchain.images = make([]VK_Image, image_count)
	} else {
		ensure(u32(len(swapchain.images)) == image_count)
	}

	temporary_images := make([]vk.Image, image_count)
	defer delete(temporary_images)

	vk_fatal(vk.GetSwapchainImagesKHR(vk_context.device.logical, swapchain.handle, &image_count, raw_data(temporary_images)))
	for image, i in temporary_images {		
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
		vk_fatal(vk.CreateImageView(vk_context.device.logical, &image_view_create_info, nil, &swapchain.images[i].view))

		stored_image := &swapchain.images[i]
		stored_image.handle = image
		stored_image.extent = {attributes.extent.width, attributes.extent.height, 1}
		stored_image.format = image_view_create_info.format
		stored_image.subresource_range = image_view_create_info.subresourceRange

		log.info("Vulkan: Successfully created swapchain image-view", i+1)
	}

	if swapchain.on_recreation == nil do swapchain.on_recreation = make([dynamic]proc(vk.Extent2D))
	
	vk_context.swapchain.initialised = true
}

vk_swapchain_destroy :: proc() {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	ensure(vk_context.swapchain.initialised)

	for &image in vk_context.swapchain.images do vk.DestroyImageView(vk_context.device.logical, image.view, nil)
	vk.DestroySwapchainKHR(vk_context.device.logical, vk_context.swapchain.handle, nil)
}

vk_swapchain_recreate :: proc(
	allocator := context.allocator
) {
	context.allocator = allocator
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	ensure(vk_context.swapchain.initialised)

	width, height: i32
	for width == 0 || height == 0 {
		width, height = window_get_framebuffer_size()
		window_wait_events()
	}

	attributes := vk_context.swapchain.attributes
	attributes.extent.width  = u32(width)
	attributes.extent.height = u32(height)
	
	vk.DeviceWaitIdle(vk_context.device.logical)
	vk_swapchain_destroy()
	vk_swapchain_create(&attributes)

	for on_recreation in vk_context.swapchain.on_recreation do on_recreation(attributes.extent)
}

vk_memory_type_find_index :: proc(
	physical_device: vk.PhysicalDevice,
	property_flags:  vk.MemoryPropertyFlags,
	type_filter:     u32
) -> (
	memory_type_index: Maybe(u32)
) {
	assert(physical_device != nil)
	
	memory_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &memory_properties)

	for type, i in memory_properties.memoryTypes {
		if bool(type_filter & (1 << u32(i))) && property_flags <= type.propertyFlags do return u32(i)
	}

	return nil
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
