package handmade

import "base:runtime"
import "core:fmt"
import "core:sys/linux"
import "core:sys/posix"

import wl "shared:wayland"
import "shared:wayland/xdg"

main :: proc() {
	global_context = context

	window.width = 800
	window.height = 600

	window.display = wl.display_connect(nil)
	if window.display == nil {panic("Could not connect to wayland display")}
	defer wl.display_disconnect(window.display)

	registry := wl.display_get_registry(window.display)
	wl.registry_add_listener(registry, &registry_listener, nil)
	wl.display_roundtrip(window.display)

	window.surface = wl.compositor_create_surface(window.compositor)
	defer wl.surface_destroy(window.surface)

	xdg.wm_base_add_listener(window.wm_base, &wm_base_listener, nil)
	window.xdg_surface = xdg.wm_base_get_xdg_surface(window.wm_base, window.surface)
	defer xdg.surface_destroy(window.xdg_surface)

	xdg.surface_add_listener(window.xdg_surface, &surface_listener, nil)
	window.toplevel = xdg.surface_get_toplevel(window.xdg_surface)
	xdg.toplevel_add_listener(window.toplevel, &toplevel_listener, nil)
	xdg.toplevel_set_title(window.toplevel, "Hellope from Odin!")

	deco_toplevel := xdg.decoration_manager_v1_get_toplevel_decoration(
		window.deco_manager,
		window.toplevel,
	)
	xdg.toplevel_decoration_v1_add_listener(deco_toplevel, &deco_toplevel_listener, nil)
	xdg.toplevel_decoration_v1_set_mode(deco_toplevel, .server_side)

	// wl.buffer_add_listener(window.buffer, &buffer_listener, nil)

	for wl.display_dispatch(window.display) != 0 {
		if window.closed do break
		wl.surface_commit(window.surface)


	}
}

window: struct {
	display:      ^wl.display,
	surface:      ^wl.surface,
	compositor:   ^wl.compositor,
	shm:          ^wl.shm,
	xdg_surface:  ^xdg.surface,
	wm_base:      ^xdg.wm_base,
	toplevel:     ^xdg.toplevel,
	deco_manager: ^xdg.decoration_manager_v1,
	buffer:       ^wl.buffer,

	width, height:	int,
	closed:			bool,
}

registry_listener := wl.registry_listener {
	global        = registry_global,
	global_remove = registry_global_remove,
}

global_context: runtime.Context

registry_global :: proc "c" (
	data: rawptr,
	registry: ^wl.registry,
	name: uint,
	interface: cstring,
	version: uint,
) {
	context = global_context
	switch interface {
	case wl.compositor_interface.name:
		window.compositor =
		cast(^wl.compositor)wl.registry_bind(registry, name, &wl.compositor_interface, 6)
	case wl.shm_interface.name:
		window.shm = cast(^wl.shm)wl.registry_bind(registry, name, &wl.shm_interface, 1)
	case xdg.wm_base_interface.name:
		window.wm_base =
		cast(^xdg.wm_base)wl.registry_bind(registry, name, &xdg.wm_base_interface, 1)
	case xdg.decoration_manager_v1_interface.name:
		window.deco_manager =
		cast(^xdg.decoration_manager_v1)wl.registry_bind(
			registry,
			name,
			&xdg.decoration_manager_v1_interface,
			1,
		)
	}
}

registry_global_remove :: proc "c" (data: rawptr, registry: ^wl.registry, name: uint) {}

wm_base_listener := xdg.wm_base_listener {
	ping = wm_base_ping,
}

wm_base_ping :: proc "c" (data: rawptr, wm_base: ^xdg.wm_base, serial: uint) {
	xdg.wm_base_pong(wm_base, serial)
}

surface_listener := xdg.surface_listener {
	configure = surface_configure,
}

surface_configure :: proc "c" (data: rawptr, surface: ^xdg.surface, serial: uint) {
	context = global_context
	xdg.surface_ack_configure(surface, serial)
	window.buffer = create_frame_buffer()
	wl.surface_attach(window.surface, window.buffer, 0, 0)
	wl.surface_commit(window.surface)
}

toplevel_listener := xdg.toplevel_listener {
	configure = toplevel_configure,
	close = toplevel_close,
}

toplevel_configure :: proc "c" (
	data: rawptr,
	toplevel: ^xdg.toplevel,
	width, height: int,
	states: xdg.array,
) {
	if width == 0 || height == 0 do return
	window.width = width
	window.height = height
}

toplevel_close :: proc "c" (data: rawptr, toplevel: ^xdg.toplevel) {
	window.closed = true
}

create_frame_buffer :: proc() -> ^wl.buffer {
	width := window.width
	height := window.height
	stride := width * 4
	size := stride * height

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
	defer linux.munmap(data_raw, uint(size))
	if err != .NONE {
		fmt.eprintln("error: couldn't map shared memory")
		return nil
	}

	data := cast([^]u32)data_raw
	pool := wl.shm_create_pool(window.shm, auto_cast fd, size)
	defer wl.shm_pool_destroy(pool)
	buffer := wl.shm_pool_create_buffer(pool, 0, width, height, stride, .xrgb8888)
	// draw checkerboard background
	for y in 0 ..< height {
		for x in 0 ..< width {
			index := y * width + x
			if (x + y / 16 * 16) % 32 < 16 do data[index] = 0xff666666
			else do data[index] = 0xffeeeeee
		}
	}

	wl.buffer_add_listener(buffer, &buffer_listener, nil)
	return buffer
}

deco_toplevel_listener := xdg.toplevel_decoration_v1_listener {
	configure = deco_toplevel_configure,
}

deco_toplevel_configure :: proc "c" (
	data: rawptr,
	toplevel: ^xdg.toplevel_decoration_v1,
	mode: xdg.toplevel_decoration_v1_mode,
) {

}

buffer_listener := wl.buffer_listener {
	release = buffer_release,
}

buffer_release :: proc "c" (data: rawptr, buffer: ^wl.buffer) {
	wl.buffer_destroy(buffer)
}
