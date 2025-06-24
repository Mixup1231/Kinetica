package core

import "core:os"
import "core:log"

import vk "vendor:vulkan"

Render_Target :: u32
Color         :: [4]f32

render_get_next_target :: proc(
	signal_image_available: Semaphore,
	in_flight:              Fence
) -> (
	render_target: Render_Target
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	ensure(vk_context.swapchain.initialised)

	in_flight := in_flight

	vk_warn(vk.WaitForFences(vk_context.device.logical, 1, &in_flight, true, max(u64)))
	vk_warn(vk.ResetFences(vk_context.device.logical, 1, &in_flight))

	result := vk.AcquireNextImageKHR(
		vk_context.device.logical,
		vk_context.swapchain.handle,
		max(u64),
		signal_image_available,
		0,
		transmute(^u32)&render_target
	)

	if result == .ERROR_OUT_OF_DATE_KHR {
		log.info("Vulkan - Swapchain: Need to recreate swapchain.")
	}
	
	if result != .SUCCESS && result != .SUBOPTIMAL_KHR {
		log.fatal("Vulkan - Swapchain: Failed to acquire next swapchain image, exiting...")
		os.exit(-1)
	}

	return render_target
}

// NOTE(Mitchell): Still early and not abstracted well
render_begin :: proc(
	command_buffer: Command_Buffer,
	render_target:  Render_Target,
	clear_color:    Color
) {	
	ensure(vk_context.initialised)
	ensure(vk_context.swapchain.initialised)
	ensure(0 <= render_target)
	ensure(render_target < u32(len(vk_context.swapchain.image_views)))
	
	command_buffer_reset(command_buffer)
	command_buffer_begin(command_buffer, {.One_Time_Submit})
	
	barrier: vk.ImageMemoryBarrier = {
		sType               = .IMAGE_MEMORY_BARRIER,
		dstAccessMask       = {.COLOR_ATTACHMENT_WRITE},
		oldLayout           = .UNDEFINED,
		newLayout           = .COLOR_ATTACHMENT_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image               = vk_context.swapchain.images[render_target],
		subresourceRange    = {
			aspectMask     = {.COLOR},
			baseMipLevel   = 0,
			levelCount     = 1,
			baseArrayLayer = 0,
			layerCount     = 1
		},		
	}

	vk.CmdPipelineBarrier(
		command_buffer,
		{.TOP_OF_PIPE},
		{.COLOR_ATTACHMENT_OUTPUT},
		{},
		0, nil,
		0, nil,
		1, &barrier
	)
	
	clear_value: vk.ClearValue
	clear_value.color.float32 = clear_color
	
	// TODO(Mitchell): Make loadOp and storeOp configurable
	color_attachment_info: vk.RenderingAttachmentInfoKHR = {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = vk_context.swapchain.image_views[render_target],
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
		clearValue  = clear_value
	}

	// TODO(Mitchell): May want to make renderArea configurable for VR
	rendering_info: vk.RenderingInfo = {
		sType                = .RENDERING_INFO,
		layerCount           = 1,
		colorAttachmentCount = 1,
		pColorAttachments    = &color_attachment_info, 
		renderArea           = {
			offset = {0, 0},
			extent = vk_context.swapchain.attributes.extent
		},
	}	
	
	vk.CmdBeginRendering(command_buffer, &rendering_info)
}

render_end :: proc(
	render_target:          Render_Target,
	command_buffer:         Command_Buffer,
	wait_image_available:   Semaphore,
	signal_render_finished: Semaphore,
	in_flight:              Fence,
) {
	ensure(vk_context.initialised)
	ensure(vk_context.device.initialised)
	ensure(vk_context.swapchain.initialised)
	
	render_target  := render_target
	command_buffer := command_buffer
	in_flight      := in_flight
	
	vk.CmdEndRendering(command_buffer)

	barrier: vk.ImageMemoryBarrier = {
		sType               = .IMAGE_MEMORY_BARRIER,
		srcAccessMask       = {.COLOR_ATTACHMENT_WRITE},
		oldLayout           = .COLOR_ATTACHMENT_OPTIMAL,
		newLayout           = .PRESENT_SRC_KHR,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image               = vk_context.swapchain.images[render_target],
		subresourceRange    = {
			aspectMask     = {.COLOR},
			baseMipLevel   = 0,
			levelCount     = 1,
			baseArrayLayer = 0,
			layerCount     = 1
		}
	}

	vk.CmdPipelineBarrier(
		command_buffer,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.BOTTOM_OF_PIPE},
		{},
		0, nil,
		0, nil,
		1, &barrier
	)
	
	vk_warn(vk.EndCommandBuffer(command_buffer))	

	image_available: []Semaphore = {wait_image_available}
	render_finished: []Semaphore = {signal_render_finished}
	wait_stage:      []vk.PipelineStageFlags = {{.COLOR_ATTACHMENT_OUTPUT}}

	submit_info: vk.SubmitInfo = {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = raw_data(image_available),
		pWaitDstStageMask    = raw_data(wait_stage),
		commandBufferCount   = 1,
		pCommandBuffers      = &command_buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = raw_data(render_finished)
	}

	vk_warn(vk.QueueSubmit(vk_context.device.queues[.Graphics], 1, &submit_info, in_flight))
	vk.WaitForFences(vk_context.device.logical, 1, &in_flight, true, max(u64))

	swapchain: []vk.SwapchainKHR = {vk_context.swapchain.handle}
	
	present_info: vk.PresentInfoKHR = {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = raw_data(render_finished),
		swapchainCount     = 1,
		pSwapchains        = raw_data(swapchain),
		pImageIndices      = &render_target
	}

	vk.QueuePresentKHR(vk_context.device.queues[.Present], &present_info)
}

// TODO(Mitchell): Will need to accepts multiple viewports for VR
render_set_viewport :: proc(
	command_buffer: Command_Buffer,
	viewport:       Viewport
) {
	vk_viewport: vk.Viewport = {
		x        = viewport.x,
		y        = viewport.y,
		width    = viewport.width,
		height   = viewport.height,
		minDepth = 0,
		maxDepth = 1
	}
	vk.CmdSetViewport(command_buffer, 0, 1, &vk_viewport)

	vk_scissor: vk.Rect2D = {
		offset = {
			i32(viewport.x),
			i32(viewport.y),
		},
		extent = {
			width  = u32(viewport.width),
			height = u32(viewport.height)
		}
	}
	vk.CmdSetScissor(command_buffer, 0, 1, &vk_scissor)
}

render_draw :: proc(
	command_buffer: Command_Buffer,
	vertext_count:  u32,
	instance_count: u32 = 1,
	first_vertex:   u32 = 0,
	first_instance: u32 = 0
) {
	ensure(command_buffer != nil)

	vk.CmdDraw(command_buffer, vertext_count, instance_count, first_vertex, first_instance)
}
