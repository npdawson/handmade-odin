package handmade

import "core:fmt"

import sdl "vendor:sdl3"

main :: proc() {
	if ok := sdl.Init({.VIDEO}); !ok {
		fmt.eprintfln("SDL Init error: %v", sdl.GetError())
		panic("Could not initialize SDL!")
	}

	window := sdl.CreateWindow("Handmade Odin", 800, 600, nil)
	if window == nil {
		fmt.eprintfln("SDL CreateWindow error: %v", sdl.GetError())
		panic("Could not create window")
	}
	defer sdl.DestroyWindow(window)

	surface := sdl.CreateSurface(800, 600, sdl.PixelFormat.RGBA32)
	screen_surface := sdl.GetWindowSurface(window)

	running := true
	for running {
		event: sdl.Event
		if sdl.PollEvent(&event) {
			#partial switch event.type {
			case .WINDOW_CLOSE_REQUESTED, .QUIT:
				running = false
			}
		}

		sdl.ClearSurface(surface, 0.5, 1.0, 1.0, sdl.ALPHA_OPAQUE_FLOAT)
		sdl.BlitSurface(surface, nil, screen_surface, nil)
		sdl.UpdateWindowSurface(window)
	}
}
