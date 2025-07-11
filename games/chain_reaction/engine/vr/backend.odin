package vr

import "../../../../kinetica/core"
import oxr "../../dependencies/openxr_odin/openxr"
import "base:runtime"
import "core:slice"
import "core:strings"
import vk "vendor:vulkan"

@(private)
VR_Context :: struct {
	odin_ctx:              runtime.Context,
	instance:              oxr.Instance,
	system_id:             oxr.SystemId,
	app_info:              App_Info,
	debug_messenger:       oxr.DebugUtilsMessengerEXT,
	session:               oxr.Session,
	view_config:           []oxr.ViewConfigurationView,
	view_type:             oxr.ViewConfigurationType,
	swapchain_infos:       []Swapchain_Info,
	environment_blendmode: oxr.EnvironmentBlendMode,
	reference_space:       oxr.Space,
	session_running:       bool,
}

Swapchain_Info :: struct {
	swapchain:        oxr.Swapchain,
	swapchain_format: i64,
	image_views:      []vk.ImageView,
}

App_Info :: struct {
	api_version:         u64,
	app_name:            string,
	app_version:         u32,
	engine_name:         string,
	engine_version:      u32,
	extensions_required: []cstring,
}

Render_Layer_Info :: struct {
	predicted_display_time: oxr.Time,
	layers:                 []^oxr.CompositionLayerBaseHeader,
	layer_projection:       oxr.CompositionLayerProjection,
	layer_projection_views: [dynamic]oxr.CompositionLayerProjectionView,
}

@(private)
oxr_assert :: proc(result: oxr.Result, message: string) {
	if result != .SUCCESS {
		core.topic_fatal(.VR, result, message)
	}
}

@(private, require_results)
get_instance :: proc(
	app_info: oxr.ApplicationInfo,
	extensions_required: ^[]cstring,
) -> (
	instance: oxr.Instance,
) {
	info := oxr.InstanceCreateInfo {
		sType                 = .INSTANCE_CREATE_INFO,
		applicationInfo       = app_info,
		enabledExtensionCount = u32(len(extensions_required)),
		enabledExtensionNames = raw_data(extensions_required[:]),
	}
	result := oxr.CreateInstance(&info, &instance)
	oxr_assert(result, "Failed to create instance")
	return instance
}

@(private, require_results)
get_system_id :: proc(
	form_factor: oxr.FormFactor,
	instance: oxr.Instance,
) -> (
	system_id: oxr.SystemId,
) {
	info := oxr.SystemGetInfo {
		sType      = .SYSTEM_GET_INFO,
		formFactor = form_factor,
	}
	result := oxr.GetSystem(instance, &info, &system_id)
	oxr_assert(result, "Failed to get system id")
	return system_id
}

@(private)
get_extensions :: proc() -> (extensions: []oxr.ExtensionProperties) {
	count: u32
	result := oxr.EnumerateInstanceExtensionProperties(nil, 0, &count, nil)
	oxr_assert(result, "Could not get the instance extension count")
	core.topic_info(.VR, "There are", count, "available extensions")
	extensions = make([]oxr.ExtensionProperties, count)
	for &e in extensions {
		e.sType = .EXTENSION_PROPERTIES
	}
	result = oxr.EnumerateInstanceExtensionProperties(nil, count, &count, raw_data(extensions))
	oxr_assert(result, "Failed to get available extensions")
	for &e in extensions {
		core.topic_info(
			.VR,
			"Available Extension:",
			strings.trim_null(transmute(string)e.extensionName[:]),
		)
	}
	return extensions
}

create_debug_messenger :: proc(instance: oxr.Instance) -> (messenger: oxr.DebugUtilsMessengerEXT) {
	info := oxr.DebugUtilsMessengerCreateInfoEXT {
		sType             = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverities = {.VERBOSE, .INFO, .WARNING, .ERROR},
		messageTypes      = {.GENERAL, .VALIDATION, .PERFORMANCE, .CONFORMANCE},
		userCallback      = debug_callback,
	}
	result := oxr.CreateDebugUtilsMessengerEXT(instance, &info, &messenger)
	oxr_assert(result, "Failed to create debug messenger")
	return messenger
}

debug_callback :: proc "c" (
	severity: oxr.DebugUtilsMessageSeverityFlagsEXT,
	type: oxr.DebugUtilsMessageTypeFlagsEXT,
	callback_data: ^oxr.DebugUtilsMessengerCallbackDataEXT,
	user_data: rawptr,
) -> (
	false: rawptr,
) {
	context = vr_ctx.odin_ctx
	core.topic_warn(.VR, "VR validation message:", severity, type, callback_data)
	return false
}

@(private)
create_session :: proc(
	instance: oxr.Instance,
	system_id: oxr.SystemId,
	vk_info: core.Vulkan_Info,
) -> (
	session: oxr.Session,
) {
	physical_device: vk.PhysicalDevice
	result := oxr.GetVulkanGraphicsDeviceKHR(
		instance,
		system_id,
		vk_info.instance,
		&physical_device,
	)
	vulkan_info := oxr.GraphicsBindingVulkanKHR {
		sType            = .GRAPHICS_BINDING_VULKAN_KHR,
		instance         = vk_info.instance,
		physicalDevice   = physical_device,
		device           = vk_info.logical_device,
		queueFamilyIndex = 0,
		queueIndex       = 0,
	}
	session_info := oxr.SessionCreateInfo {
		sType    = .SESSION_CREATE_INFO,
		next     = &vulkan_info,
		systemId = system_id,
	}
	result = oxr.CreateSession(instance, &session_info, &session)
	oxr_assert(result, "Failed to create session")
	return session

}

@(private)
begin_session :: proc(session: oxr.Session) {
	info := oxr.SessionBeginInfo {
		sType                        = .SESSION_BEGIN_INFO,
		primaryViewConfigurationType = .PRIMARY_STEREO,
	}
	result := oxr.BeginSession(session, &info)
	oxr_assert(result, "Failed to begin session")
	core.topic_info(.VR, "Session has begun")
}

@(private)
get_view_configuration :: proc(
	instance: oxr.Instance,
	id: oxr.SystemId,
) -> (
	view_configs: []oxr.ViewConfigurationView,
	view_type: oxr.ViewConfigurationType,
) {
	count: u32
	result := oxr.EnumerateViewConfigurations(instance, id, 0, &count, nil)
	oxr_assert(result, "Failed to get view config types")
	view_config_types := make([]oxr.ViewConfigurationType, count)
	defer delete(view_config_types)
	result = oxr.EnumerateViewConfigurations(instance, id, count, &count, &view_config_types[0])
	oxr_assert(result, "Failed to get view configurations")

	result = oxr.EnumerateViewConfigurationViews(
		instance,
		id,
		view_config_types[0],
		0,
		&count,
		nil,
	)
	oxr_assert(result, "Failed to get count of view configuration views")
	view_configs = make([]oxr.ViewConfigurationView, count)
	for &v in view_configs {
		v.sType = .VIEW_CONFIGURATION_VIEW
	}
	result = oxr.EnumerateViewConfigurationViews(
		instance,
		id,
		view_config_types[0],
		count,
		&count,
		&view_configs[0],
	)
	oxr_assert(result, "Failed to get view config views")
	core.topic_info(.VR, view_configs)
	return view_configs, view_config_types[0]
}

@(private)
setup_swapchain :: proc(
	session: oxr.Session,
	vk_info: core.Vulkan_Info,
	view_config: []oxr.ViewConfigurationView,
) -> (
	swapchain: []oxr.Swapchain,
) {
	count: u32
	result := oxr.EnumerateSwapchainFormats(session, 0, &count, nil)
	oxr_assert(result, "Failed to count swapchain formats")
	formats := make([]i64, count)
	result = oxr.EnumerateSwapchainFormats(session, count, &count, &formats[0])
	oxr_assert(result, "Failed to get swapchain formats")
	core.topic_info(.VR, "Swapchain formats:", formats)
	core.topic_info(.VR, "Swapchain format required:", vk_info.swapchain_image_format)
	assert(slice.contains(formats, i64(vk_info.swapchain_image_format)))

	swapchain = make([]oxr.Swapchain, len(view_config))

	for &s, i in swapchain {
		info := oxr.SwapchainCreateInfo {
			sType       = .SWAPCHAIN_CREATE_INFO,
			usageFlags  = {.COLOR_ATTACHMENT, .SAMPLED},
			format      = i64(vk_info.swapchain_image_format),
			sampleCount = view_config[i].recommendedSwapchainSampleCount,
			width       = view_config[i].recommendedImageRectWidth,
			height      = view_config[i].recommendedImageRectHeight,
			faceCount   = 1,
			arraySize   = 1,
			mipCount    = 1,
		}
		core.topic_info(.VR, info)
		result = oxr.CreateSwapchain(session, &info, &s)
		oxr_assert(result, "Failed to create oxr swapchain")
		core.topic_info(.VR, "Creted swapchain:", s)
	}
	return swapchain
}

get_swapchain_images :: proc(swapchain: oxr.Swapchain) -> (images: []oxr.SwapchainImageVulkanKHR) {
	count: u32
	result := oxr.EnumerateSwapchainImages(swapchain, 0, &count, nil)
	oxr_assert(result, "failed to get swapchain image count")
	core.topic_info(.VR, "No. of swapchain images:", count)
	images = make([]oxr.SwapchainImageVulkanKHR, count)
	for &i in images {
		i.sType = .SWAPCHAIN_IMAGE_VULKAN_KHR
	}
	core.topic_info(.VR, images)
	result = oxr.EnumerateSwapchainImages(
		swapchain,
		count,
		&count,
		transmute(^oxr.SwapchainImageBaseHeader)&images[0],
	)
	oxr_assert(result, "Failed to get swapchain images")
	core.topic_info(.VR, images)
	return images
}

get_swapchain_image_views :: proc(
	images: ^[]oxr.SwapchainImageVulkanKHR,
	vk_info: core.Vulkan_Info,
) -> (
	vk_image_views: []vk.ImageView,
) {
	vk_image_views = make([]vk.ImageView, len(images))
	for image, i in images {
		subresource_range := vk.ImageSubresourceRange {
			layerCount = 1,
			levelCount = 1,
			aspectMask = {.COLOR},
		}
		info := vk.ImageViewCreateInfo {
			sType            = .IMAGE_VIEW_CREATE_INFO,
			image            = image.image,
			viewType         = .D2,
			format           = vk_info.swapchain_image_format,
			subresourceRange = subresource_range,
		}
		result := vk.CreateImageView(vk_info.logical_device, &info, nil, &vk_image_views[i])
		if result != .SUCCESS {
			core.topic_error(.VR, "Failed to create image views")
		} else {
			core.topic_info(.VR, "Created image view:", vk_image_views[i])
		}
	}
	return vk_image_views
}

get_environment_mode :: proc(
	instance: oxr.Instance,
	id: oxr.SystemId,
) -> (
	blendmode: oxr.EnvironmentBlendMode,
) {
	count: u32
	result := oxr.EnumerateEnvironmentBlendModes(instance, id, .PRIMARY_STEREO, 0, &count, nil)
	oxr_assert(result, "Failed to count environment modes")
	modes := make([]oxr.EnvironmentBlendMode, count)
	result = oxr.EnumerateEnvironmentBlendModes(
		instance,
		id,
		.PRIMARY_STEREO,
		count,
		&count,
		&modes[0],
	)
	oxr_assert(result, "Failed to get environment modes")
	core.topic_info(.VR, "Environment Modes:", modes)
	for mode in modes {
		if mode == .OPAQUE {
			return .OPAQUE
		}
	}
	core.topic_error(.VR, "Could not find any blend mode but defaulting to opaque")
	return .OPAQUE
}

get_reference_space :: proc(session: oxr.Session) -> (space: oxr.Space) {
	pose := oxr.Posef {
		orientation = oxr.Quaternionf{w = 1},
	}
	info := oxr.ReferenceSpaceCreateInfo {
		sType                = .REFERENCE_SPACE_CREATE_INFO,
		referenceSpaceType   = .LOCAL,
		poseInReferenceSpace = pose,
	}
	result := oxr.CreateReferenceSpace(session, &info, &space)
	oxr_assert(result, "Failed to create reference space")
	return space
}

