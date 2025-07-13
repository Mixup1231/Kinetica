package core

import "base:runtime"
import "core:log"
import "core:os"

Logger_User :: enum {
	All,
	Jack,
	Mitch,
}

Logger_Topic :: enum {
	All,
	Core,
	Graphics,
	Input,
	VR,
}

@(private = "file")
Logger_Context :: struct {
	user:  Logger_User,
	topic: Logger_Topic,
}

@(private = "file")
logger_ctx: Logger_Context

init_logger :: proc(
	file: string,
	user := Logger_User.All,
	topic := Logger_Topic.All,
) -> log.Logger {
	logger_ctx = {user, topic}
	// Create terminal logger
	info_opt := log.Options {
		.Level,
		.Short_File_Path,
		.Line,
		.Procedure,
		.Terminal_Color,
		.Thread_Id,
	}
	info_log := log.create_console_logger(.Info, info_opt, "", context.allocator)
	context.logger = info_log

	// Create file logger
	os.remove(file)
	handle, err := os.open(file, os.O_CREATE | os.O_WRONLY) // TODO: Bug here i think i need to clear the file contents
	if err != nil {
		log.fatal("Failed to open file logger")
	}
	debug_log := log.create_file_logger(
		handle,
		.Debug,
		log.Default_File_Logger_Opts,
		"",
		context.allocator,
	)

	logger := log.create_multi_logger(debug_log, info_log, allocator = context.allocator)
	log.info("Created logger")
	return logger
}

@(disabled = RELEASE)
user_debug :: proc(user: Logger_User, args: ..any, location := #caller_location) {
	if logger_ctx.user != .All && user != logger_ctx.user && user != .All {
		return
	}
	log.debug(user, ":", location,  args)
}

@(disabled = RELEASE)
user_info :: proc(user: Logger_User, args: ..any, location := #caller_location) {
	if logger_ctx.user != .All && user != logger_ctx.user && user != .All {
		return
	}
	log.info(user, ":", location,  args)
}

@(disabled = RELEASE)
user_warn :: proc(user: Logger_User, args: ..any, location := #caller_location) {
	if logger_ctx.user != .All && user != logger_ctx.user && user != .All {
		return
	}
	log.warn(user, ":", location,  args)
}

@(disabled = RELEASE)
user_error :: proc(user: Logger_User, args: ..any, location := #caller_location) {
	if logger_ctx.user != .All && user != logger_ctx.user && user != .All {
		return
	}
	log.error(user, ":", location,  args)
}

@(disabled = RELEASE)
user_fatal :: proc(user: Logger_User, args: ..any, location := #caller_location) {
	if logger_ctx.user != .All && user != logger_ctx.user && user != .All {
		return
	}
	log.fatal(user, ":",  location, args)
}

@(disabled = RELEASE)
topic_debug :: proc(topic: Logger_Topic, args: ..any, location := #caller_location) {
	if logger_ctx.topic != .All && topic != logger_ctx.topic && topic != .All {
		return
	}
	log.debug(topic, ":",  location, args)
}

@(disabled = RELEASE)
topic_info :: proc(topic: Logger_Topic, args: ..any, location := #caller_location) {
	if logger_ctx.topic != .All && topic != logger_ctx.topic && topic != .All {
		return
	}
	log.info(topic, ":",  location, args)
}

@(disabled = RELEASE)
topic_warn :: proc(topic: Logger_Topic, args: ..any, location := #caller_location) {
	if logger_ctx.topic != .All && topic != logger_ctx.topic && topic != .All {
		return
	}
	log.warn(topic, ":",  location, args)
}

@(disabled = RELEASE)
topic_error :: proc(topic: Logger_Topic, args: ..any, location := #caller_location) {
	if logger_ctx.topic != .All && topic != logger_ctx.topic && topic != .All {
		return
	}
	log.error(topic, ":", location, args)
}

@(disabled = RELEASE)
topic_fatal :: proc(topic: Logger_Topic, args: ..any, location := #caller_location) {
	if logger_ctx.topic != .All && topic != logger_ctx.topic && topic != .All {
		return
	}
	log.fatal(topic, ":", location, args)
}

