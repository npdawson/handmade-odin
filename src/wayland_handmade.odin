#+build linux
package handmade

import "base:runtime"

import "core:fmt"
import "core:os"
import "core:slice"
import "core:sys/linux"
import "core:sys/posix"

import wl "shared:wayland"
import decor "shared:wayland/ext/libdecor"
import wp "shared:wayland/wp"

import ev "libevdev"

Buffer :: struct {
	wl_buffer:     ^wl.buffer,
	width, height: int,
	data:          rawptr,
	size:          uint,
}

Window :: struct {
	display:                             ^wl.display,
	compositor:                          ^wl.compositor,
	subcompositor:                       ^wl.subcompositor,
	main_surface:                        ^wl.surface,
	game_surface:                        ^wl.surface,
	game_subsurface:                     ^wl.subsurface,
	shm:                                 ^wl.shm,
	frame:                               ^decor.frame,
	state:                               decor.window_state,
	viewporter:                          ^wp.viewporter,
	viewport:                            ^wp.viewport,
	main_buffer:                         ^Buffer,
	game_buffer:                         ^Buffer,
	configured_width, configured_height: int,
	floating_width, floating_height:     int,
	last_frame:                          uint,
	offset:                              f64,
	running:                             bool,
}

Dpad :: enum {
	UP,
	DOWN,
	LEFT,
	RIGHT,
}
Dpad_Set :: bit_set[Dpad]

Button :: enum {
	Circle,
	Cross,
	Triangle,
	Square,
	Start,
	Select,
	L1,
	L2,
	L3,
	R1,
	R2,
	R3,
	Home,
}
Button_Set :: bit_set[Button]

Stick :: struct {
	x, y: i32,
}

gamepad: struct {
	dpad:        Dpad_Set,
	buttons:     Button_Set,
	left_stick:  Stick,
	right_stick: Stick,
}

main :: proc() {
	window: Window
	window.running = true

	window.display = wl.display_connect(nil)
	if window.display == nil {
		fmt.println("Could not connect to wayland display")
		x11_main()
		return
	}
	defer wl.display_disconnect(window.display)

	registry := wl.display_get_registry(window.display)
	wl.registry_add_listener(registry, &registry_listener, &window)
	wl.display_roundtrip(window.display)

	window.main_surface = wl.compositor_create_surface(window.compositor)
	defer wl.surface_destroy(window.main_surface)
	window.game_surface = wl.compositor_create_surface(window.compositor)
	defer wl.surface_destroy(window.game_surface)
	window.game_subsurface = wl.subcompositor_get_subsurface(
		window.subcompositor,
		window.game_surface,
		window.main_surface,
	)
	defer wl.subsurface_destroy(window.game_subsurface)

	window.viewport = wp.viewporter_get_viewport(window.viewporter, window.game_surface)
	defer wp.viewport_destroy(window.viewport)

	window.game_buffer = create_shm_buffer(&window, 1280, 720)

	decor_instance := decor.new(window.display, &iface)
	window.frame = decor.decorate(decor_instance, window.main_surface, &frame_iface, &window)

	decor.frame_set_app_id(window.frame, "handmade-libdecor")
	decor.frame_set_title(window.frame, "Handmade Odin")
	decor.frame_map(window.frame)

	cb := wl.surface_frame(window.main_surface)
	wl.callback_add_listener(cb, &frame_listener, &window)

	pad_fd, err := linux.open("/dev/input/by-id/usb-Sony_Interactive_Entertainment_DualSense_Wireless_Controller-if03-event-joystick", {.NONBLOCK})
	if err != .NONE {
		fmt.eprintln("Failed to open gamepad", err)
		panic("")
	}
	dev := ev.new()
	ev.set_fd(dev, pad_fd)
	fmt.printfln("Device Name: %v", ev.get_name(dev))
	for window.running {
		event: ev.input_event
		for window.running && ev.next_event(dev, {.NORMAL}, &event) == 0 {
			type := ev.event_type_get_name(event.type)
			code := ev.event_code_get_name(event.type, event.code)
			button: Maybe(Button)
			dpad: Maybe(Dpad)
			#partial switch event.type {
			case .KEY, .ABS:
				switch event.code {
				case .ABS_X:
					gamepad.left_stick.x = event.value - 128
				case .ABS_Y:
					gamepad.left_stick.y = event.value - 128
				case .ABS_RX:
					gamepad.right_stick.x = event.value - 128
				case .ABS_RY:
					gamepad.right_stick.y = event.value - 128
				case .BTN_NORTH:
					button = .Triangle
				case .BTN_SOUTH:
					button = .Cross
				case .BTN_EAST:
					button = .Circle
				case .BTN_WEST:
					button = .Square
				case .BTN_SELECT:
					button = .Select
				case .BTN_START:
					button = .Start
				case .ABS_HAT0X:
					switch event.value {
					case -1:
						dpad = .LEFT
					case 0:
						gamepad.dpad -= { .LEFT, .RIGHT }
					case 1:
						dpad = .RIGHT
					}
				case .ABS_HAT0Y:
					switch event.value {
					case -1:
						dpad = .UP
					case 0:
						gamepad.dpad -= { .UP, .DOWN }
					case 1:
						dpad = .DOWN
					}
				case .BTN_TL:
					button = .L1
				case .BTN_TR:
					button = .R1
				case .BTN_TL2:
					button = .L2
				case .BTN_TR2:
					button = .R2
				case .BTN_MODE:
					button = .Home
				case .BTN_THUMBL:
					button = .L3
				case .BTN_THUMBR:
					button = .R3
				case .ABS_Z, .ABS_RZ:
				case:
					fmt.printfln("Event: %v %v %v", type, code, event.value)
				}
			case .SYN:
				if code == "SYN_DROPPED" {
					// when a SYN_DROPPED event is received, the client must:
					// * discard all events since the last SYN_REPORT
					// * discard all events up to and including the next SYN_REPORT
					panic("SYN_DROPPED: not handling events fast enough")
				}
			}
			b, b_ok := button.?
			d, d_ok := dpad.?
			if b_ok {
				if event.value == 1 {
					gamepad.buttons += {b}
				} else if event.value == 0 {
					gamepad.buttons -= {b}
				}
			}
			if d_ok {
				gamepad.dpad += {d}
			}
		}
		if decor.dispatch(decor_instance, -1) < 0 {
			window.running = false
		}
	}
}

deadzone :: proc(value: i32) -> bool {
	return value <= 133 && value >= 123
}

iface := decor.interface {
	error = handle_error,
}

handle_error :: proc "c" (instance: ^decor.instance, error: decor.error, message: cstring) {
	context = runtime.default_context()
	fmt.eprintfln("libdecor error (%v): %v", error, message)
	os.exit(1)
}

frame_iface := decor.frame_interface {
	configure = handle_configure,
	close     = handle_close,
	commit    = handle_commit,
}

handle_configure :: proc "c" (frame: ^decor.frame, config: ^decor.configuration, data: rawptr) {
	context = runtime.default_context()
	window := cast(^Window)data

	if ok := decor.configuration_get_window_state(config, &window.state); !ok {
		fmt.eprintfln("couldn't get window state: %v", window.state)
	}

	width, height: int
	if ok := decor.configuration_get_content_size(config, frame, &width, &height); !ok {
		width = window.game_buffer.width
		height = window.game_buffer.height
	}

	width = (width == 0) ? window.floating_width : width
	height = (height == 0) ? window.floating_height : height

	window.configured_width = width
	window.configured_height = height

	state := decor.state_new(width, height)
	decor.frame_commit(frame, state, config)
	decor.state_free(state)

	if decor.frame_is_floating(frame) {
		window.floating_width = width
		window.floating_height = height
	}

	view_width, view_height: int
	width_offset, height_offset: int
	ratio := f64(width) / f64(height)
	if ratio >= (16.0 / 9.0) {
		view_width = int(f64(height) * 16.0 / 9.0)
		view_height = height
		width_offset = (width - view_width) / 2.0
	} else {
		view_width = width
		view_height = int(f64(width) * 9.0 / 16.0)
		height_offset = (height - view_height) / 2.0
	}

	wl.subsurface_set_position(window.game_subsurface, width_offset, height_offset)
	wp.viewport_set_destination(window.viewport, view_width, view_height)

	draw_frame(window)
}

handle_close :: proc "c" (frame: ^decor.frame, data: rawptr) {
	// context = runtime.default_context()
	window := cast(^Window)data
	window.running = false
	// os.exit(0)
}

handle_commit :: proc "c" (frame: ^decor.frame, data: rawptr) {
	window := cast(^Window)data
	wl.surface_commit(window.main_surface)
}

registry_listener := wl.registry_listener {
	global        = registry_global,
	global_remove = registry_global_remove,
}

registry_global :: proc "c" (
	data: rawptr,
	registry: ^wl.registry,
	name: uint,
	interface: cstring,
	version: uint,
) {
	context = runtime.default_context()
	window := cast(^Window)data
	switch interface {
	case wl.compositor_interface.name:
		window.compositor =
		cast(^wl.compositor)wl.registry_bind(registry, name, &wl.compositor_interface, 6)
	case wl.subcompositor_interface.name:
		window.subcompositor =
		cast(^wl.subcompositor)wl.registry_bind(registry, name, &wl.subcompositor_interface, 1)
	case wl.shm_interface.name:
		window.shm = cast(^wl.shm)wl.registry_bind(registry, name, &wl.shm_interface, 1)
	case wp.viewporter_interface.name:
		window.viewporter =
		cast(^wp.viewporter)wl.registry_bind(registry, name, &wp.viewporter_interface, 1)
	case:
	// fmt.printfln("unhandled interface: %v", interface)
	}
}

registry_global_remove :: proc "c" (data: rawptr, registry: ^wl.registry, name: uint) {}

create_shm_buffer :: proc(window: ^Window, width, height: int) -> ^Buffer {
	stride := width * 4
	size := stride * height

	name := fmt.caprintf("/wl_shm_%v", cast(uintptr)window.display) // needs to be random?
	fd := posix.shm_open(name, {.RDWR, .CREAT, .EXCL}, {.IRUSR, .IWUSR})
	posix.shm_unlink(name)
	defer posix.close(fd)
	if fd < 0 {
		fmt.eprintln("error: couldn't create shared memory.", posix.errno())
	}

	ret := posix.ftruncate(fd, auto_cast size)
	if ret == .FAIL {
		fmt.eprintln("error: couldn't do ftruncate on shared memory descriptor")
	}

	data_raw, err := linux.mmap(0, uint(size), {.READ, .WRITE}, {.SHARED}, auto_cast fd, 0)
	if err != .NONE {
		fmt.eprintln("error: couldn't map shared memory")
	}

	buffer := new(Buffer)
	buffer.width = width
	buffer.height = height
	buffer.data = data_raw
	buffer.size = uint(size)
	pool := wl.shm_create_pool(window.shm, auto_cast fd, size)
	defer wl.shm_pool_destroy(pool)
	buffer.wl_buffer = wl.shm_pool_create_buffer(pool, 0, width, height, stride, .xrgb8888)

	// wl.buffer_add_listener(buffer.wl_buffer, &buffer_listener, &buffer)
	return buffer
}

draw_frame :: proc(window: ^Window) {
	main_buffer := window.main_buffer
	game_buffer := window.game_buffer

	if main_buffer != nil {
		linux.munmap(main_buffer.data, main_buffer.size)
		wl.buffer_destroy(main_buffer.wl_buffer)
		free(main_buffer)
	}
	main_buffer = create_shm_buffer(window, window.configured_width, window.configured_height)

	paint_buffer(game_buffer, window)

	wl.surface_attach(window.game_surface, game_buffer.wl_buffer, 0, 0)
	wl.surface_attach(window.main_surface, main_buffer.wl_buffer, 0, 0)
	wl.surface_damage_buffer(window.game_surface, 0, 0, game_buffer.width, game_buffer.height)
	wl.surface_damage_buffer(window.main_surface, 0, 0, main_buffer.width, main_buffer.height)
	wl.surface_commit(window.game_surface)
	wl.surface_commit(window.main_surface)
}

frame_done :: proc "c" (data: rawptr, cb: ^wl.callback, time: uint) {
	context = runtime.default_context()
	// destroy the old callback
	wl.callback_destroy(cb)
	// and create a new one
	window := cast(^Window)data
	new_cb := wl.surface_frame(window.main_surface)
	wl.callback_add_listener(new_cb, &frame_listener, window)

	// update at specific delta time
	if window.last_frame != 0 {
		elapsed := time - window.last_frame
		window.offset += f64(elapsed) / 1000 * 60 // pixels? per second
	}

	// submit a frame
	draw_frame(window)

	window.last_frame = time
}

frame_listener := wl.callback_listener {
	done = frame_done,
}

blue_offset := 0
green_offset := 0

paint_buffer :: proc(buffer: ^Buffer, window: ^Window) {
	pixels := slice.from_ptr(cast([^]u32)buffer.data, int(buffer.size / 4))
	if .LEFT in gamepad.dpad {
		blue_offset += 1
	} else if .RIGHT in gamepad.dpad {
		blue_offset -= 1
	}
	if .UP in gamepad.dpad {
		green_offset += 1
	} else if .DOWN in gamepad.dpad {
		green_offset -= 1
	}
	// draw gradient
	for y in 0 ..< buffer.height {
		for x in 0 ..< buffer.width {
			index := y * buffer.width + x
			blue := (x + blue_offset) & 0xff
			green := (y + green_offset) & 0xff
			pixels[index] = u32(green << 8 | blue)
			// if (x + y / 16 * 16) % 32 < 16 do pixels[index] = 0xff666666
			// else do pixels[index] = 0xffeeeeee
		}
	}
}

buffer_listener := wl.buffer_listener {
	release = buffer_release,
}

buffer_release :: proc "c" (data: rawptr, wl_buffer: ^wl.buffer) {
	context = runtime.default_context()
	buffer := cast(^Buffer)data
	linux.munmap(buffer.data, buffer.size)
	wl.buffer_destroy(buffer.wl_buffer)
	free(buffer)
}
