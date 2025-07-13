package vr

import "../../../../kinetica/core"
import oxr "../../dependencies/openxr_odin/openxr"
import "core:strings"
import la "core:math/linalg"
import vk "vendor:vulkan"

import "core:log"


@(private)
vr_ctx := VR_Context {
	app_info = App_Info {
		api_version = oxr.MAKE_VERSION(1, 0, 25),
		app_name = "Example App",
		app_version = 1,
		engine_name = "Example Engine",
		engine_version = 1,
		extensions_required = {"XR_EXT_debug_utils", "XR_KHR_vulkan_enable"},
	},
}
init :: proc(vk_ctx: core.Vulkan_Info) {
	vr_ctx.odin_ctx = context
	oxr.load_base_procs()
	if (oxr.CreateInstance == nil) {
		core.topic_fatal(.VR, "Failed to load basic function pointers")
	}
	app_info := oxr.ApplicationInfo {
		apiVersion         = vr_ctx.app_info.api_version,
		applicationName    = oxr.make_string(vr_ctx.app_info.app_name, 128),
		applicationVersion = vr_ctx.app_info.app_version,
		engineName         = oxr.make_string(vr_ctx.app_info.engine_name, 128),
		engineVersion      = vr_ctx.app_info.engine_version,
	}
	// Get instance will fail if no runtime
	vr_ctx.instance = get_instance(app_info, &vr_ctx.app_info.extensions_required)
	core.topic_info(.VR, "Created VR instance")
	oxr.load_instance_procs(vr_ctx.instance)
	if (oxr.GetSystem == nil) {
		core.topic_fatal(.VR, "Failed to get all openxr function pointers")
	}
	core.topic_info(.VR, "Obtained all openxr function pointers")


	// Get system id will fail of headset not connected
	vr_ctx.system_id = get_system_id(.HEAD_MOUNTED_DISPLAY, vr_ctx.instance)
	core.topic_info(.VR, "Got system id:", vr_ctx.system_id)

	// Print system avail extensions
	get_extensions()

	vr_ctx.debug_messenger = create_debug_messenger(vr_ctx.instance)

	// Find Required Vulkan links
	get_vulkan_reqs(vr_ctx.instance, vr_ctx.system_id)

	// Link vulkan
	vr_ctx.session = create_session(vr_ctx.instance, vr_ctx.system_id, vk_ctx)
	core.topic_info(.VR, "Successfully openxr created session")
}

// TODO: Improve polling for non success
event_poll :: proc(vk_info: core.Vulkan_Info) -> (should_render: bool) {
	data := oxr.EventDataBuffer {
		sType = .EVENT_DATA_BUFFER,
	}
	result := oxr.PollEvent(vr_ctx.instance, &data)
	if result != .SUCCESS {
		return vr_ctx.session_running
	}
	session_state_change := transmute(^oxr.EventDataSessionStateChanged)&data
	core.topic_info(.VR, data.sType, session_state_change)
	if session_state_change.state == .READY {
		vr_ctx.session_running = true
		begin_session(vr_ctx.session)
		vr_ctx.view_config, vr_ctx.view_type = get_view_configuration(
			vr_ctx.instance,
			vr_ctx.system_id,
		)
		swapchains := setup_swapchain(vr_ctx.session, vk_info, vr_ctx.view_config)
		vr_ctx.swapchain_infos = make([]Swapchain_Info, len(swapchains))
		for &s, i in vr_ctx.swapchain_infos {
			s.swapchain = swapchains[i]
			s.swapchain_format = i64(vk_info.swapchain_image_format)
			s.width = i32(vr_ctx.view_config[i].recommendedImageRectWidth)
			s.height = i32(vr_ctx.view_config[i].recommendedImageRectHeight)
			
			swapchain_images := get_swapchain_images(s.swapchain)
			defer delete(swapchain_images)
			if s.images == nil do s.images = make([]OXR_Image, len(swapchain_images))
			for image, j in swapchain_images {
				s.images[j].handle = image.image
			}
			swapchain_image_views := get_swapchain_image_views(&swapchain_images, vk_info)
			defer delete(swapchain_image_views)
			for view, j in swapchain_image_views {
				s.images[j].view = view
			}
		}
		vr_ctx.environment_blendmode = get_environment_mode(vr_ctx.instance, vr_ctx.system_id)
		vr_ctx.reference_space = get_reference_space(vr_ctx.session)
	}
	return session_state_change.state == .FOCUSED || session_state_change.state == .VISIBLE
}

destroy :: proc() {
	oxr.DestroyInstance(vr_ctx.instance)
	oxr.DestroySession(vr_ctx.session)
}

get_vulkan_reqs :: proc(instance: oxr.Instance, id: oxr.SystemId) {
	// Get required API version
	graphics_reqs := oxr.GraphicsRequirementsVulkanKHR {
		sType = .GRAPHICS_REQUIREMENTS_VULKAN_KHR,
	}
	result := oxr.GetVulkanGraphicsRequirementsKHR(instance, id, &graphics_reqs)
	oxr_assert(result, "Failed to get vulkan graphics reqs")
	core.topic_info(.VR, "Vulkan graphics requirements:", graphics_reqs)

	// Get Required Extensions
	count: u32
	oxr.GetVulkanInstanceExtensionsKHR(instance, id, 0, &count, nil)
	list := make([]u8, count)
	builder := strings.builder_from_bytes(list)
	extensions := strings.to_cstring(&builder)
	oxr.GetVulkanInstanceExtensionsKHR(instance, id, count, &count, extensions)
	core.topic_info(.VR, "Extensions Required:", extensions)

	// Get Required Extensions
	oxr.GetVulkanDeviceExtensionsKHR(instance, id, 0, &count, nil)
	list = make([]u8, count)
	builder = strings.builder_from_bytes(list)
	extensions = strings.to_cstring(&builder)
	oxr.GetVulkanDeviceExtensionsKHR(instance, id, count, &count, extensions)
	core.topic_info(.VR, "Extensions Required:", extensions)
}

get_swapchain_images_info :: proc() -> (images_info: Swapchain_Images_Info, is_valid: bool) {
	if len(vr_ctx.swapchain_infos) == 0 do return {}, false
	
	swapchain_info := &vr_ctx.swapchain_infos[0]
	view_config := &vr_ctx.view_config[0]

	images_info = {
		extent = {
			width = view_config.recommendedImageRectWidth,
			height = view_config.recommendedImageRectHeight,
		},
		format = swapchain_info.swapchain_format,
		count = u32(len(swapchain_info.images))
	}

	return images_info, true
}

get_view_projection :: proc(fov: ^oxr.Fovf, nearz, farz: f32, pose: ^oxr.Posef) -> (view_projection: matrix[4, 4]f32) {
	
	left  := la.tan(fov.angleLeft)
	right := la.tan(fov.angleRight)
	up    := la.tan(fov.angleUp)
	down  := la.tan(fov.angleDown)

	width := right - left
	height := down - up
	offset := f32(0)

	view_projection = {
		2.0 / width, 0.0, (right + left) / width, 0.0,
		0.0, 2.0 / height, (up + down) / height, 0.0,
		0.0, 0.0, -(farz + offset) / (farz - nearz), -(farz * (nearz + offset)) / (farz - nearz),
		0.0, 0.0, -1.0, 0.0,
	}

	position: [3]f32 = {pose.position.x, pose.position.y, pose.position.z}
	orientation := quaternion(
		real = pose.orientation.w,
		imag = pose.orientation.x,
		jmag = pose.orientation.y,
		kmag = pose.orientation.z
	)

	view := la.inverse(la.matrix4_translate_f32(position) * la.matrix4_from_quaternion_f32(orientation))
	
	return view_projection * view
}

begin_frame :: proc() -> (frame_data: OXR_Frame_Data) {
	frame_data.frame_state = {
		sType = .FRAME_STATE
	}
	frame_wait: oxr.FrameWaitInfo = {
		sType = .FRAME_WAIT_INFO
	}
	result := oxr.WaitFrame(vr_ctx.session, &frame_wait, &frame_data.frame_state)
	oxr_assert(result, "Failed to wait for vr frame.")

	frame_begin: oxr.FrameBeginInfo = {
		sType = .FRAME_BEGIN_INFO
	}
	result = oxr.BeginFrame(vr_ctx.session, &frame_begin)
	oxr_assert(result, "Failed to begin vr frame.")

	frame_data.render_info = {
		layer_projection = {
			sType = .COMPOSITION_LAYER_PROJECTION,
			space = vr_ctx.reference_space,
		}
	}
	
	for i in 0..<vr_ctx.view_count {
		frame_data.views[i] = {
			sType = .VIEW
		}
	}
	view_state: oxr.ViewState = {
		sType = .VIEW_STATE
	}
	view_locate_info: oxr.ViewLocateInfo = {
		sType                 = .VIEW_LOCATE_INFO,
		viewConfigurationType = .PRIMARY_STEREO,
		displayTime           = frame_data.frame_state.predictedDisplayTime,
		space                 = vr_ctx.reference_space,
	}
	result = oxr.LocateViews(vr_ctx.session, &view_locate_info, &view_state, vr_ctx.view_count, &vr_ctx.view_submit_count, &frame_data.views[0])
	oxr_assert(result, "Failed to locate vr views")

	frame_data.submit_count = vr_ctx.view_submit_count
	for i in 0..<vr_ctx.view_submit_count {
		swapchain_info := &vr_ctx.swapchain_infos[i]
		frame_data.render_info.layer_projection_views[i] = {
			sType    = .COMPOSITION_LAYER_PROJECTION_VIEW,
			pose     = frame_data.views[i].pose,
			fov      = frame_data.views[i].fov,
			subImage = {
				swapchain       = swapchain_info.swapchain,
				imageArrayIndex = 0,
				imageRect       = {
					offset = {0, 0},
					extent = {swapchain_info.width, swapchain_info.height}
				}
			}
		}
	}

	return frame_data
}

acquire_next_swapchain_image :: proc(submit_index: u32) -> (image: OXR_Image) {
	assert(submit_index < u32(len(vr_ctx.swapchain_infos)))
	
	swapchain_info := &vr_ctx.swapchain_infos[submit_index]
	image_index: u32
	acquire_info: oxr.SwapchainImageAcquireInfo = {
		sType = .SWAPCHAIN_IMAGE_ACQUIRE_INFO
	}
	result := oxr.AcquireSwapchainImage(swapchain_info.swapchain, &acquire_info, &image_index)
	oxr_assert(result, "Failed to acquire vr swapchain image")

	wait_info: oxr.SwapchainImageWaitInfo = {
		sType   = .SWAPCHAIN_IMAGE_WAIT_INFO,
		timeout = max(i64)
	}
	result = oxr.WaitSwapchainImage(swapchain_info.swapchain, &wait_info)
	oxr_assert(result, "Failed to wait for vr swapchain image")

	image = swapchain_info.images[image_index]
	image.extent = {u32(swapchain_info.width), u32(swapchain_info.height)}
	image.index = image_index

	return image
}

release_swapchain_image :: proc(submit_index: u32) {
	assert(submit_index < u32(len(vr_ctx.swapchain_infos)))

	release_info: oxr.SwapchainImageReleaseInfo = {
		sType = .SWAPCHAIN_IMAGE_RELEASE_INFO,
	}
	result := oxr.ReleaseSwapchainImage(vr_ctx.swapchain_infos[submit_index].swapchain, &release_info)
	oxr_assert(result, "Failed to release vr swapchain image")
}

end_frame :: proc(frame_data: ^OXR_Frame_Data) {
	assert(frame_data != nil)

	frame_data.render_info.layer_projection.viewCount = frame_data.submit_count
	frame_data.render_info.layer_projection.views = &frame_data.render_info.layer_projection_views[0]

	layers := cast(^oxr.CompositionLayerBaseHeader)&frame_data.render_info.layer_projection
	frame_end: oxr.FrameEndInfo = {
		sType                = .FRAME_END_INFO,
		displayTime          = frame_data.frame_state.predictedDisplayTime,
		environmentBlendMode = vr_ctx.environment_blendmode,
		layerCount           = frame_data.frame_state.shouldRender ? 1 : 0,
		layers               = frame_data.frame_state.shouldRender ? &layers : nil
	}
	result := oxr.EndFrame(vr_ctx.session, &frame_end)
	oxr_assert(result, "Failed to end vr frame")
}
