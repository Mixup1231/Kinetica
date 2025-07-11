package vr

import "../../../../kinetica/core"
import oxr "../../dependencies/openxr_odin/openxr"
import "core:strings"
import vk "vendor:vulkan"

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
			swapchain_images := get_swapchain_images(s.swapchain)
			s.image_views = get_swapchain_image_views(&swapchain_images, vk_info)
		}
		vr_ctx.environment_blendmode = get_environment_mode(vr_ctx.instance, vr_ctx.system_id)
		vr_ctx.reference_space = get_reference_space(vr_ctx.session)
	}
	return vr_ctx.session_running
}

render_frame :: proc() {
	// Wait for render_frame
	frame_state := oxr.FrameState {
		sType = .FRAME_STATE,
	}
	wait_info := oxr.FrameWaitInfo {
		sType = .FRAME_WAIT_INFO,
	}
	result := oxr.WaitFrame(vr_ctx.session, &wait_info, &frame_state)
	oxr_assert(result, "XR Frame state invalid")

	// Begin Frame
	begin_info := oxr.FrameBeginInfo {
		sType = .FRAME_BEGIN_INFO,
	}
	result = oxr.BeginFrame(vr_ctx.session, &begin_info)
	oxr_assert(result, "XR frame failed to begin")

	// Render
	render_info := Render_Layer_Info {
		predicted_display_time = frame_state.predictedDisplayTime,
		layer_projection = {sType = .COMPOSITION_LAYER_PROJECTION},
	}
	render_info.layers = make([]^oxr.CompositionLayerBaseHeader, 1)
	
	rendered: bool
	if frame_state.shouldRender {
		rendered := render_layer(&render_info, vr_ctx.session)
		if rendered {
			render_info.layers[0] =
			transmute(^oxr.CompositionLayerBaseHeader)&render_info.layer_projection
		}

	}

	// End Frame
	end_info := oxr.FrameEndInfo {
		sType                = .FRAME_END_INFO,
		displayTime          = frame_state.predictedDisplayTime,
		environmentBlendMode = vr_ctx.environment_blendmode,
		layerCount           = 0,
		// layers               = raw_data(render_info.layers),
	}
	result = oxr.EndFrame(vr_ctx.session, &end_info)
	oxr_assert(result, "Failed to end xr frame")
}

// NOTE(Mitchell): May want to take in a buffer of image views and resize if needed instead of allocating each frame
begin_frame :: proc(allocator := context.allocator) -> (frame_state: oxr.FrameState, render_info: Render_Layer_Info, image_views: []vk.ImageView) {
	context.allocator = allocator
	
	// Wait for render_frame
	frame_state = oxr.FrameState {
		sType = .FRAME_STATE,
	}
	wait_info := oxr.FrameWaitInfo {
		sType = .FRAME_WAIT_INFO,
	}
	result := oxr.WaitFrame(vr_ctx.session, &wait_info, &frame_state)
	oxr_assert(result, "XR Frame state invalid")

	// Begin Frame
	begin_info := oxr.FrameBeginInfo {
		sType = .FRAME_BEGIN_INFO,
	}
	result = oxr.BeginFrame(vr_ctx.session, &begin_info)
	oxr_assert(result, "XR frame failed to begin")
	
	render_info = Render_Layer_Info {
		predicted_display_time = frame_state.predictedDisplayTime,
		layer_projection = {sType = .COMPOSITION_LAYER_PROJECTION},
	}
	
	render_info.layers = make([]^oxr.CompositionLayerBaseHeader, 1)
	views := make([]oxr.View, len(vr_ctx.view_config))
	for &v in views {
		v.sType = .VIEW
	}
	view_state := oxr.ViewState {
		sType = .VIEW_STATE,
	}
	view_locate_info := oxr.ViewLocateInfo {
		sType                 = .VIEW_LOCATE_INFO,
		displayTime           = render_info.predicted_display_time,
		viewConfigurationType = vr_ctx.view_type,
		space                 = vr_ctx.reference_space,
	}
	count: u32
	result = oxr.LocateViews(
		vr_ctx.session,
		&view_locate_info,
		&view_state,
		u32(len(views)),
		&count,
		&views[0],
	)
	oxr_assert(result, "Failed to locate views")
	resize(&render_info.layer_projection_views, count)

	image_views = make([]vk.ImageView, count)
	
	for i in 0 ..< count {
		image_index: u32
		swapchain_info := &vr_ctx.swapchain_infos[i]
		aquire_info := oxr.SwapchainImageAcquireInfo {
			sType = .SWAPCHAIN_IMAGE_ACQUIRE_INFO,
		}
		result = oxr.AcquireSwapchainImage(swapchain_info.swapchain, &aquire_info, &image_index)
		oxr_assert(result, "Failed to aquire image from colour swapchain")
		wait_info := oxr.SwapchainImageWaitInfo {
			sType   = .SWAPCHAIN_IMAGE_WAIT_INFO,
			timeout = i64(max(i32)),
		}
		result = oxr.WaitSwapchainImage(swapchain_info.swapchain, &wait_info)
		oxr_assert(result, "Failed to wait for image from colour swapchain")
		width := vr_ctx.view_config[i].recommendedImageRectWidth
		height := vr_ctx.view_config[i].recommendedImageRectHeight
		viewport := vk.Viewport {
			width    = f32(width),
			height   = f32(height),
			maxDepth = 1,
		}
		scissor := vk.Rect2D {
			extent = {width, height},
		}
		nearZ := 0.05
		farZ := 100
		image_rect := oxr.Rect2Di {
			extent = {i32(width), i32(height)},
		}
		sub_image := oxr.SwapchainSubImage {
			swapchain = swapchain_info.swapchain,
			imageRect = image_rect,
		}
		render_info.layer_projection_views[i] = oxr.CompositionLayerProjectionView {
			sType    = .COMPOSITION_LAYER_PROJECTION_VIEW,
			pose     = views[i].pose,
			fov      = views[i].fov,
			subImage = sub_image,
		}

		image_views[i] = swapchain_info.image_views[i]
	}

	return frame_state, render_info, image_views
}

end_frame :: proc(frame_state: ^oxr.FrameState, render_info: ^Render_Layer_Info) {
	assert(frame_state != nil)
	assert(render_info != nil)
	
	render_info.layer_projection.layerFlags = {
		.BLEND_TEXTURE_SOURCE_ALPHA,
		.CORRECT_CHROMATIC_ABERRATION,
	}
	render_info.layer_projection.space = vr_ctx.reference_space
	render_info.layer_projection.viewCount = u32(len(render_info.layer_projection_views))
	render_info.layer_projection.views = &render_info.layer_projection_views[0]
	
	// End Frame
	end_info := oxr.FrameEndInfo {
		sType                = .FRAME_END_INFO,
		displayTime          = frame_state.predictedDisplayTime,
		environmentBlendMode = vr_ctx.environment_blendmode,
		layerCount           = 0,
		// layers               = raw_data(render_info.layers),
	}
	result := oxr.EndFrame(vr_ctx.session, &end_info)
	oxr_assert(result, "Failed to end xr frame")
}

release_render_view :: proc(index: u32) {
	assert(index < u32(len(vr_ctx.swapchain_infos)))
	
	release_info := oxr.SwapchainImageReleaseInfo {
		sType = .SWAPCHAIN_IMAGE_RELEASE_INFO,
	}
	result := oxr.ReleaseSwapchainImage(vr_ctx.swapchain_infos[index].swapchain, &release_info)
	oxr_assert(result, "Failed to release image back to swapchain")
}

render_layer :: proc(render_info: ^Render_Layer_Info, session: oxr.Session) -> (rendered: bool) {
	views := make([]oxr.View, len(vr_ctx.view_config))
	for &v in views {
		v.sType = .VIEW
	}
	view_state := oxr.ViewState {
		sType = .VIEW_STATE,
	}
	view_locate_info := oxr.ViewLocateInfo {
		sType                 = .VIEW_LOCATE_INFO,
		displayTime           = render_info.predicted_display_time,
		viewConfigurationType = vr_ctx.view_type,
		space                 = vr_ctx.reference_space,
	}
	count: u32
	result := oxr.LocateViews(
		session,
		&view_locate_info,
		&view_state,
		u32(len(views)),
		&count,
		&views[0],
	)
	oxr_assert(result, "Failed to locate views")
	resize(&render_info.layer_projection_views, count)

	for i in 0 ..< count {
		image_index: u32
		swapchain_info := &vr_ctx.swapchain_infos[i]
		aquire_info := oxr.SwapchainImageAcquireInfo {
			sType = .SWAPCHAIN_IMAGE_ACQUIRE_INFO,
		}
		result = oxr.AcquireSwapchainImage(swapchain_info.swapchain, &aquire_info, &image_index)
		oxr_assert(result, "Failed to aquire image from colour swapchain")
		wait_info := oxr.SwapchainImageWaitInfo {
			sType   = .SWAPCHAIN_IMAGE_WAIT_INFO,
			timeout = i64(max(i32)),
		}
		result = oxr.WaitSwapchainImage(swapchain_info.swapchain, &wait_info)
		oxr_assert(result, "Failed to wait for image from colour swapchain")
		width := vr_ctx.view_config[i].recommendedImageRectWidth
		height := vr_ctx.view_config[i].recommendedImageRectHeight
		viewport := vk.Viewport {
			width    = f32(width),
			height   = f32(height),
			maxDepth = 1,
		}
		scissor := vk.Rect2D {
			extent = {width, height},
		}
		nearZ := 0.05
		farZ := 100
		image_rect := oxr.Rect2Di {
			extent = {i32(width), i32(height)},
		}
		sub_image := oxr.SwapchainSubImage {
			swapchain = swapchain_info.swapchain,
			imageRect = image_rect,
		}
		render_info.layer_projection_views[i] = oxr.CompositionLayerProjectionView {
			sType    = .COMPOSITION_LAYER_PROJECTION_VIEW,
			pose     = views[i].pose,
			fov      = views[i].fov,
			subImage = sub_image,
		}

		// Tell Graphics API to begin rendering
		// core.render_color_vr(swapchain_info.image_views[image_index])

		release_info := oxr.SwapchainImageReleaseInfo {
			sType = .SWAPCHAIN_IMAGE_RELEASE_INFO,
		}
		result = oxr.ReleaseSwapchainImage(swapchain_info.swapchain, &release_info)
		oxr_assert(result, "Failed to release image back to swapchain")
	}
	render_info.layer_projection.layerFlags = {
		.BLEND_TEXTURE_SOURCE_ALPHA,
		.CORRECT_CHROMATIC_ABERRATION,
	}
	render_info.layer_projection.space = vr_ctx.reference_space
	render_info.layer_projection.viewCount = u32(len(render_info.layer_projection_views))
	render_info.layer_projection.views = &render_info.layer_projection_views[0]
	return true
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
		count = u32(len(swapchain_info.image_views))
	}

	return images_info, true
}

