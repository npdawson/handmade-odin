package libevdev

import "core:sys/linux"

libevdev :: struct {
}

timeval :: struct {
	seconds:      i64,
	microseconds: i64,
}

input_event :: struct {
	time:  timeval,
	type:  Event_Type,
	code:  Event_Code,
	value: i32,
}

Read_Flag :: enum u32 {
	SYNC       = 1,
	NORMAL     = 2,
	FORCE_SYNC = 4,
	BLOCKING   = 8,
}
Read_Flag_Set :: bit_set[Read_Flag]

Log_Priority :: enum {
	ERROR = 10,
	INFO  = 20,
	DEBUG = 30,
}

Grab_Mode :: enum {
	GRAB   = 3,
	UNGRAB = 4,
}

Read_Status :: enum {
	SUCCESS = 0,
	SYNC    = 1,
}

Event_Type :: enum u16 {
	SYN       = 0x0,
	KEY       = 0x1,
	REL       = 0x2,
	ABS       = 0x3,
	MSC       = 0x4,
	SW        = 0x5,
	LED       = 0x11,
	SND       = 0x12,
	REP       = 0x14,
	FF        = 0x15,
	PWR       = 0x16,
	FF_STATUS = 0x17,
	MAX       = 0x1f,
	CNT       = MAX + 1,
}

Event_Code :: enum u16 {
	ABS_X      = 0x00,
	ABS_Y      = 0x01,
	ABS_Z      = 0x02,
	ABS_RX     = 0x03,
	ABS_RY     = 0x04,
	ABS_RZ     = 0x05,
	ABS_HAT0X  = 0x10,
	ABS_HAT0Y  = 0x11,
	BTN_SOUTH  = 0x130,
	BTN_EAST   = 0x131,
	BTN_NORTH  = 0x133,
	BTN_WEST   = 0x134,
	BTN_TL     = 0x136,
	BTN_TR     = 0x137,
	BTN_TL2    = 0x138,
	BTN_TR2    = 0x139,
	BTN_SELECT = 0x13a,
	BTN_START  = 0x13b,
	BTN_MODE   = 0x13c,
	BTN_THUMBL = 0x13d,
	BTN_THUMBR = 0x13e,
}

// log_func_t :: #type proc "c" (
// 	priority: Log_Priority,
// 	data: rawptr,
// 	file: cstring,
// 	line: i32,
// 	func: cstring,
// 	format: cstring,
// 	#c_vararg args: ..any,
// )
//
// device_log_func_t :: #type proc "c" (
// 	dev: ^libevdev,
// 	priority: Log_Priority,
// 	data: rawptr,
// 	file: cstring,
// 	line: i32,
// 	func: cstring,
// 	format: cstring,
// 	#c_vararg args: ..any,
// )

foreign import evdev "system:evdev"

@(default_calling_convention = "c", link_prefix = "libevdev_")
foreign evdev {
	new :: proc() -> ^libevdev ---
	// new_from_fd :: proc(fd: linux.Fd, dev: ^^libevdev) ---
	free :: proc(dev: ^libevdev) ---
	// set_log_function :: proc(logfunc: ^log_func_t, data: rawptr) ---
	// set_log_priority :: proc(priority: Log_Priority) ---
	// set_device_log_function
	grab :: proc(dev: ^libevdev, grab: Grab_Mode) ---
	set_fd :: proc(dev: ^libevdev, fd: linux.Fd) -> i32 ---
	change_fd :: proc(dev: ^libevdev, fd: linux.Fd) -> i32 ---
	get_fd :: proc(dev: ^libevdev) -> linux.Fd ---
	next_event :: proc(dev: ^libevdev, flags: Read_Flag_Set, ev: ^input_event) -> i32 ---
	has_event_pending :: proc(dev: ^libevdev) -> i32 ---
	get_name :: proc(dev: ^libevdev) -> cstring ---
	set_name :: proc(dev: ^libevdev, name: cstring) ---
	get_phys :: proc(dev: ^libevdev) -> cstring ---
	set_phys :: proc(dev: ^libevdev, phys: cstring) ---

	has_event_type :: proc(dev: ^libevdev, type: Event_Type) -> i32 ---
	has_event_code :: proc(dev: ^libevdev, type: Event_Type, code: Event_Code) -> i32 ---
	event_type_get_name :: proc(type: Event_Type) -> cstring ---
	event_code_get_name :: proc(type: Event_Type, code: Event_Code) -> cstring ---
	set_event_value :: proc(dev: ^libevdev, type: Event_Type, code: Event_Code, value: i32) -> i32 ---
}
