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

Buffer :: struct {
	wl_buffer:     ^wl.buffer,
	width, height: int,
	data:          rawptr,
	size:          uint,
}

Window :: struct {
	display:                             ^wl.display,
	surface:                             ^wl.surface,
	compositor:                          ^wl.compositor,
	shm:                                 ^wl.shm,
	frame:                               ^decor.frame,
	state:                               decor.window_state,
	viewporter:                          ^wp.viewporter,
	viewport:                            ^wp.viewport,
	buffer:                              ^Buffer,
	configured_width, configured_height: int,
	floating_width, floating_height:     int,
	last_frame:                          uint,
	offset:                              f64,
	running:                             bool,
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

	window.surface = wl.compositor_create_surface(window.compositor)
	defer wl.surface_destroy(window.surface)

	window.viewport = wp.viewporter_get_viewport(window.viewporter, window.surface)
	defer wp.viewport_destroy(window.viewport)

	create_shm_buffer(&window, 1280, 720)

	decor_instance := decor.new(window.display, &iface)
	window.frame = decor.decorate(decor_instance, window.surface, &frame_iface, &window)

	decor.frame_set_app_id(window.frame, "handmade-libdecor")
	decor.frame_set_title(window.frame, "Handmade Odin")
	decor.frame_map(window.frame)

	cb := wl.surface_frame(window.surface)
	wl.callback_add_listener(cb, &frame_listener, &window)

	for decor.dispatch(decor_instance, -1) >= 0 {
	}

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
		width = window.buffer.width
		height = window.buffer.height
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

	wp.viewport_set_destination(window.viewport, width, height)

	draw_frame(window)
}

handle_close :: proc "c" (frame: ^decor.frame, data: rawptr) {
	// context = runtime.default_context()
	// window := cast(^Window)data
	// window.running = false
	os.exit(0)
}

handle_commit :: proc "c" (frame: ^decor.frame, data: rawptr) {
	window := cast(^Window)data
	wl.surface_commit(window.surface)
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
	case wl.shm_interface.name:
		window.shm = cast(^wl.shm)wl.registry_bind(registry, name, &wl.shm_interface, 1)
	case wp.viewporter_interface.name:
		window.viewporter =
		cast(^wp.viewporter)wl.registry_bind(registry, name, &wp.viewporter_interface, 1)
	case wp.viewport_interface.name:
		fmt.println("viewport interface")
	}
}

registry_global_remove :: proc "c" (data: rawptr, registry: ^wl.registry, name: uint) {}

create_shm_buffer :: proc(window: ^Window, width, height: int) {
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

	wl.buffer_add_listener(buffer.wl_buffer, &buffer_listener, buffer)
	// TODO: figure out how to properly set the source rectangle
	// wp.viewport_set_source(window.viewport, 0, 0, i32(buffer.width), i32(buffer.height))
	window.buffer = buffer
}

draw_frame :: proc(window: ^Window) {
	buffer := window.buffer

	paint_buffer(buffer, window)

	wl.surface_attach(window.surface, buffer.wl_buffer, 0, 0)
	wl.surface_damage_buffer(window.surface, 0, 0, buffer.width, buffer.height)
	wl.surface_commit(window.surface)
}

frame_done :: proc "c" (data: rawptr, cb: ^wl.callback, time: uint) {
	context = runtime.default_context()
	// destroy the old callback
	wl.callback_destroy(cb)
	// and create a new one
	window := cast(^Window)data
	new_cb := wl.surface_frame(window.surface)
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

paint_buffer :: proc(buffer: ^Buffer, window: ^Window) {
	pixels := slice.from_ptr(cast([^]u32)buffer.data, int(buffer.size / 4))
	blue_offset := int(window.offset)
	green_offset := int(window.offset) * 2
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
