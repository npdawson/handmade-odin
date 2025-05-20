package handmade

import X "vendor:x11/xlib"

main :: proc() {
	display := X.OpenDisplay(nil)
	root_window := X.DefaultRootWindow(display)

	window_width: u32 = 800
	window_height: u32 = 600
	window_border_size: u32 = 0
	window_depth: i32 = 0
	window_class: X.WindowClass = .CopyFromParent
	window_visual := X.Visual{}
	attribute_mask: X.WindowAttributeMask = { .CWBackPixel, .CWEventMask }
	window_attributes := X.XSetWindowAttributes{}
	window_attributes.background_pixel = 0xffafe9af
	window_attributes.event_mask = { .StructureNotify, .KeyPress, .KeyRelease, .Exposure }

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
		&window_visual,
		attribute_mask,
		&window_attributes,
	)
	X.MapWindow(display, main_window)
	X.Flush(display)

	window_is_open := true
	for window_is_open {
		event := X.XEvent{}
		X.NextEvent(display, &event)

		#partial switch event.type {
		case .KeyPress, .KeyRelease:
			if cast(u8)event.xkey.keycode == X.KeysymToKeycode(display, .XK_Escape) {
				window_is_open = false
			}
		}
	}
}
