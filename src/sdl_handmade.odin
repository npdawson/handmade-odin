package handmade

import "core:fmt"

import sdl "vendor:sdl3"

main :: proc() {
	if ok := sdl.Init({.VIDEO}); !ok {
		fmt.eprintfln("SDL Init error: %v", sdl.GetError())
		panic("Could not initialize SDL!")
	}
}
