package core

@(private = "file")
callbacks: [dynamic]proc()

update_callbacks :: proc() {
	if callbacks == nil {
		return
	}
	for c in callbacks {
		c()
	}
}

add_update_callback :: proc(func: proc()) {
	if callbacks == nil {
		callbacks = make([dynamic]proc())
	}
	append(&callbacks, func)
}

delete_update_callback :: proc(func: proc()) {
	for c, i in callbacks {
		if c == func {
			unordered_remove(&callbacks, i)
		}
	}
}

delete_all_updates :: proc() {
	delete(callbacks)
}

