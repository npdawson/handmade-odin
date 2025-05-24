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

Buffer :: struct {
	wl_buffer: ^wl.buffer,
	data:      rawptr,
	size:      uint,
}

Window :: struct {
	display:                             ^wl.display,
	surface:                             ^wl.surface,
	compositor:                          ^wl.compositor,
	shm:                                 ^wl.shm,
	frame:                               ^decor.frame,
	state:                               decor.window_state,
	buffer:                              ^Buffer,
	configured_width, configured_height: int,
	content_width, content_height:       int,
	floating_width, floating_height:     int,
	running:                             bool,
}

main :: proc() {
	window: Window
	window.configured_width = 800
	window.configured_height = 600
	window.floating_width = 800
	window.floating_height = 600
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

	decor_instance := decor.new(window.display, &iface)
	window.frame = decor.decorate(decor_instance, window.surface, &frame_iface, &window)

	decor.frame_set_app_id(window.frame, "handmade-libdecor")
	decor.frame_set_title(window.frame, "Handmade Odin")
	decor.frame_map(window.frame)

	timeout := 16 // TODO: is this milliseconds?
	for window.running {
		if decor.dispatch(decor_instance, timeout) < 0 {
			os.exit(1)
		}
		blue_offset += 1
		green_offset += 2
		// redraw(&window)
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
		width = window.content_width
		height = window.content_height
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

	resize(window)
	redraw(window)
}

handle_close :: proc "c" (frame: ^decor.frame, data: rawptr) {
	// context = runtime.default_context()
	window := cast(^Window)data
	window.running = false
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
	}
}

registry_global_remove :: proc "c" (data: rawptr, registry: ^wl.registry, name: uint) {}

create_shm_buffer :: proc(window: ^Window) -> ^Buffer {
	stride := window.configured_width * 4
	size := stride * window.configured_height

	name := fmt.caprintf("/wl_shm_%v", cast(uintptr)window.display) // needs to be random?
	fd := posix.shm_open(name, {.RDWR, .CREAT, .EXCL}, {.IRUSR, .IWUSR})
	posix.shm_unlink(name)
	defer posix.close(fd)
	if fd < 0 {
		fmt.eprintln("error: couldn't create shared memory.", posix.errno())
		return nil
	}

	ret := posix.ftruncate(fd, auto_cast size)
	if ret == .FAIL {
		fmt.eprintln("error: couldn't do ftruncate on shared memory descriptor")
		return nil
	}

	data_raw, err := linux.mmap(0, uint(size), {.READ, .WRITE}, {.SHARED}, auto_cast fd, 0)
	if err != .NONE {
		fmt.eprintln("error: couldn't map shared memory")
		return nil
	}

	buffer := new(Buffer)
	buffer.data = data_raw
	buffer.size = uint(size)
	pool := wl.shm_create_pool(window.shm, auto_cast fd, size)
	defer wl.shm_pool_destroy(pool)
	buffer.wl_buffer = wl.shm_pool_create_buffer(
		pool,
		0,
		window.configured_width,
		window.configured_height,
		stride,
		.xrgb8888,
	)

	wl.buffer_add_listener(buffer.wl_buffer, &buffer_listener, buffer)
	return buffer
}

resize :: proc(window: ^Window) {
	// linux.munmap(window.buffer.data, window.buffer.size)
	// wl.buffer_destroy(window.buffer.wl_buffer)
	// free(window.buffer)
	window.buffer = create_shm_buffer(window)
}

redraw :: proc(window: ^Window) {
	paint_buffer(window.buffer, window)

	wl.surface_attach(window.surface, window.buffer.wl_buffer, 0, 0)
	wl.surface_damage_buffer(
		window.surface,
		0,
		0,
		window.configured_width,
		window.configured_height,
	)
	wl.surface_commit(window.surface)
}

blue_offset := 0
green_offset := 0
paint_buffer :: proc(buffer: ^Buffer, window: ^Window) {
	pixels := slice.from_ptr(cast([^]u32)buffer.data, int(buffer.size / 4))
	// draw gradient
	for y in 0 ..< window.configured_height {
		for x in 0 ..< window.configured_width {
			blue := u8(x + blue_offset)
			green := u8(y + green_offset)
			index := y * window.configured_width + x
			pixels[index] = u32(green) << 8 | u32(blue)
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
