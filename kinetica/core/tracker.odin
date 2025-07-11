package core

import "base:runtime"
import "core:log"
import "core:mem"

init_tracker :: proc() -> (^mem.Tracking_Allocator, mem.Allocator) {
	tracker := new(mem.Tracking_Allocator)
	mem.tracking_allocator_init(tracker, context.allocator)
	return tracker, mem.tracking_allocator(tracker)
}

check_tracker :: proc(tracker: ^mem.Tracking_Allocator) {
	log.info("Checking tracker allocator")
	for _, elem in tracker.allocation_map {
		log.warn("Allocation not freed:", elem.size, "bytes @", elem.location)
	}
	for elem in tracker.bad_free_array {
		log.warn("Incorrect frees:", elem.memory, "@", elem.location)
	}
}

destroy_tracker :: proc(tracker: ^mem.Tracking_Allocator) {
	check_tracker(tracker)
	assert(len(tracker.allocation_map) == 0)
	assert(len(tracker.bad_free_array) == 0)
	mem.tracking_allocator_destroy(tracker)
}

