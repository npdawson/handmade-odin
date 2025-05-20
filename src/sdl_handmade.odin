package handmade

import "core:fmt"

import sdl "vendor:sdl3"

when PLATFORM == "SDL" {
main :: proc() {
	if ok := sdl.Init({.VIDEO}); !ok {
		fmt.eprintfln("SDL Init error: %v", sdl.GetError())
		panic("Could not initialize SDL!")
	}

	window := sdl.CreateWindow("Handmade Odin", 800, 600, {.RESIZABLE})
	if window == nil {
		fmt.eprintfln("SDL CreateWindow error: %v", sdl.GetError())
		panic("Could not create window")
	}
	defer sdl.DestroyWindow(window)

	surface := sdl.CreateSurface(800, 600, .RGBA32)
	screen_surface := sdl.GetWindowSurface(window)

	running := true
	for running {
		event: sdl.Event
		if sdl.PollEvent(&event) {
			#partial switch event.type {
			case .WINDOW_CLOSE_REQUESTED, .QUIT, .WINDOW_DESTROYED:
				running = false
			case .WINDOW_RESIZED:
				width := event.window.data1
				height := event.window.data2
				sdl.DestroySurface(surface)
				surface = sdl.CreateSurface(width, height, .RGBA32)
				screen_surface = sdl.GetWindowSurface(window)
			}
		}

		sdl.ClearSurface(surface, 0.5, 0.8, 1.0, sdl.ALPHA_OPAQUE_FLOAT)
		sdl.BlitSurfaceScaled(surface, nil, screen_surface, nil, .NEAREST)
		sdl.UpdateWindowSurface(window)
	}
}

}
