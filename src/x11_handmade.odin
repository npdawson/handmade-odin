#+build linux
package handmade

import "core:fmt"
import "core:math"

import X "vendor:x11/xlib"

STATUS_ERROR :: cast(X.Status)0
TRUE_COLOR :: 4

Entity :: struct {
	x, y:          u32,
	width, height: u32,
}

Buffer :: struct {
	memory: []u8,
	size:   u64,
	width:  u32,
	height: u32,
	pitch:  u32,
}

// TODO: better merge X11 and Wayland platform layers
x11_main :: proc() {
	display := X.OpenDisplay(nil)
	root_window := X.DefaultRootWindow(display)

	default_screen := X.DefaultScreen(display)
	gfx_context := X.DefaultGC(display, default_screen)

	color_depth: i32 = 24
	visual_info := X.XVisualInfo{}
	if X.MatchVisualInfo(display, default_screen, color_depth, TRUE_COLOR, &visual_info) ==
	   STATUS_ERROR {
		fmt.eprintfln("Visual Info: %v", visual_info)
		panic("ERROR: no matching visual info")
	}
	window_width: u32 = 800
	window_height: u32 = 600
	window_border_size: u32 = 0
	window_depth := visual_info.depth
	window_class: X.WindowClass = .InputOutput
	window_visual := visual_info.visual

	attribute_mask: X.WindowAttributeMask = {.CWBackPixel, .CWEventMask}
	window_attributes := X.XSetWindowAttributes{}
	window_attributes.background_pixel = 0xffffccaa
	window_attributes.event_mask = {.StructureNotify, .KeyPress, .KeyRelease, .Exposure}

	main_window := X.CreateWindow(
		display,
		root_window,
		0,
		0,
		window_width,
		window_height,
		window_border_size,
		window_depth,
		window_class,
		window_visual,
		attribute_mask,
		&window_attributes,
	)
	X.MapWindow(display, main_window)

	X.StoreName(display, main_window, "Moving Rectangle")

	// handle "close window" requests from window manager
	wm_delete_window := X.InternAtom(display, "WM_DELETE_WINDOW", false)
	if X.SetWMProtocols(display, main_window, &wm_delete_window, 1) == STATUS_ERROR {
		fmt.eprintln("couldn't register WM_DELETE_WINDOW property")
	}

	bits_per_pixel: u32 = 32
	bytes_per_pixel := bits_per_pixel / 8

	buffer := Buffer{}
	buffer.width = window_width
	buffer.height = window_height
	buffer.pitch = buffer.width * bytes_per_pixel
	buffer.size = cast(u64)buffer.pitch * cast(u64)buffer.height
	buffer.memory = make([]u8, buffer.size)

	box := Entity {
		width  = 50,
		height = 80,
	}
	box.x = window_width / 2 - box.width / 2
	box.y = window_height / 2 - box.height / 2

	step_size: u32 = 5

	offset: i32 = 0
	bytes_between_scanlines: i32 = 0
	window_buffer := X.CreateImage(
		display,
		visual_info.visual,
		cast(u32)visual_info.depth,
		.ZPixmap,
		offset,
		raw_data(buffer.memory),
		window_width,
		window_height,
		cast(i32)bits_per_pixel,
		bytes_between_scanlines,
	)

	window_is_open := true
	for window_is_open {
		for X.Pending(display) > 0 {
			event := X.XEvent{}
			X.NextEvent(display, &event)

			#partial switch event.type {
			case .KeyPress, .KeyRelease:
				if cast(u8)event.xkey.keycode == X.KeysymToKeycode(display, .XK_Escape) {
					window_is_open = false
				} else if cast(u8)event.xkey.keycode == X.KeysymToKeycode(display, .XK_Up) {
					box.y -= step_size
				} else if cast(u8)event.xkey.keycode == X.KeysymToKeycode(display, .XK_Down) {
					box.y += step_size
				} else if cast(u8)event.xkey.keycode == X.KeysymToKeycode(display, .XK_Left) {
					box.x -= step_size
				} else if cast(u8)event.xkey.keycode == X.KeysymToKeycode(display, .XK_Right) {
					box.x += step_size
				}
			case .ClientMessage:
				if cast(X.Atom)event.xclient.data.l[0] == wm_delete_window {
					X.DestroyWindow(display, main_window)
					window_is_open = false
				}
			case .ConfigureNotify:
				window_width = cast(u32)event.xconfigure.width
				window_height = cast(u32)event.xconfigure.height

				// NOTE: delete buffer.memory slice and
				// set XImage.data pointer to 0 before XDestroyImage
				// freeing the Odin slice from C crashes with 'invalid pointer'
				delete(buffer.memory)
				window_buffer.data = nil
				X.DestroyImage(window_buffer)

				buffer.width = window_width
				buffer.height = window_height
				buffer.pitch = buffer.width * bytes_per_pixel
				buffer.size = cast(u64)buffer.pitch * cast(u64)buffer.height
				buffer.memory = make([]u8, buffer.size)
				window_buffer = X.CreateImage(
					display,
					visual_info.visual,
					cast(u32)visual_info.depth,
					.ZPixmap,
					offset,
					raw_data(buffer.memory),
					window_width,
					window_height,
					cast(i32)bits_per_pixel,
					bytes_between_scanlines,
				)
			}
		}

		do_render(&buffer, box)

		X.PutImage(
			display, main_window,
			gfx_context, window_buffer,
			0, 0,
			0, 0,
			window_width, window_height,
		)
	}
}

draw_rect :: proc(buffer: ^Buffer, pos_x, pos_y, w, h: u32, color: u32) {
	start_x := pos_x
	end_x := pos_x + w
	start_y := pos_y
	end_y := pos_y + h

	start_x = math.clamp(start_x, 0, buffer.width)
	end_x = math.clamp(end_x, 0, buffer.width)

	start_y = math.clamp(start_y, 0, buffer.height)
	end_y = math.clamp(end_y, 0, buffer.height)

	for y in start_y ..< end_y {
		for x in start_x ..< end_x {
			color_buffer := transmute([]u32)buffer.memory
			color_index := y * buffer.width + x
			color_buffer[color_index] = color
		}
	}
}

do_render :: proc(buffer: ^Buffer, box: Entity) {
	// draw bg
	draw_rect(buffer, 0, 0, buffer.width, buffer.height, 0xff87de87)
	// draw rect
	draw_rect(buffer, box.x, box.y, box.width, box.height, 0xff00aa44)
}
