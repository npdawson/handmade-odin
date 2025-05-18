package handmade

import "base:runtime"

import "core:fmt"

import sdl "vendor:sdl3"

global_ctx: runtime.Context

main :: proc() {
	global_ctx = context
	if ok := sdl.Init({.VIDEO}); !ok {
		fmt.eprintfln("SDL Init error: %v", sdl.GetError())
		panic("Could not initialize SDL!")
	}

	window: ^sdl.Window
	renderer: ^sdl.Renderer
	if ok := sdl.CreateWindowAndRenderer(
		"Handmade Odin",
		800,
		600,
		{.RESIZABLE},
		&window,
		&renderer,
	); !ok {
		if window == nil {
			fmt.eprintfln("SDL CreateWindow error: %v", sdl.GetError())
			panic("Could not create window")
		} else if renderer == nil {
			fmt.eprintfln("SDL CreateRenderer error: %v", sdl.GetError())
			panic("Could not create renderer")
		} else {
			fmt.eprintfln("Other SDL error: %v", sdl.GetError())
			panic("Could not create window and renderer")
		}
	}
	defer sdl.DestroyWindow(window)
	defer sdl.DestroyRenderer(renderer)

	// fmt.println("window pointer: %v", rawptr(window))
	// name := sdl.GetRendererName(renderer)
	// properties := sdl.GetRendererProperties(renderer)
	// fmt.printfln("Renderer name: %v", name)
	// fmt.printfln("Renderer properties: %v", properties)
	// ok := sdl.EnumerateProperties(properties, enumerate_properties_callback, nil)
	// if !ok { fmt.eprintfln("enumerate properties failed: %v", sdl.GetError()) }

	running := true
	for running {
		event: sdl.Event
		if sdl.PollEvent(&event) {
			#partial switch event.type {
			case .WINDOW_CLOSE_REQUESTED:
				running = false
			}
		}

		sdl.SetRenderDrawColorFloat(renderer, 1.0, 1.0, 1.0, sdl.ALPHA_OPAQUE_FLOAT)
		sdl.RenderClear(renderer)
		sdl.RenderPresent(renderer)
	}
}

// enumerate_properties_callback :: proc "c" (data: rawptr, props: sdl.PropertiesID, name: cstring) {
// 	context = global_ctx
// 	fmt.printfln("Property name: %v", name)
// 	type := sdl.GetPropertyType(props, name)
// 	fmt.printfln("Property type: %v", type)
// 	switch type {
// 	case .NUMBER:
// 		value := sdl.GetNumberProperty(props, name, 99)
// 		fmt.printfln("Property value: %v", value)
// 	case .FLOAT:
// 		value := sdl.GetFloatProperty(props, name, 99)
// 		fmt.printfln("Property value: %v", value)
// 	case .STRING:
// 		value := sdl.GetStringProperty(props, name, "")
// 		fmt.printfln("Property value: %v", value)
// 	case .BOOLEAN:
// 		value := sdl.GetBooleanProperty(props, name, false)
// 		fmt.printfln("Property value: %v", value)
// 	case .POINTER:
// 		value := sdl.GetPointerProperty(props, name, nil)
// 		fmt.printfln("Property value: %v", value)
// 		if name == "SDL.renderer.texture_formats" {
// 			formats := cast([^]sdl.PixelFormat)value
// 			idx := 0
// 			format := formats[idx]
// 			for format != .UNKNOWN {
// 				fmt.printfln("Supported PixelFormat: %v", format)
// 				idx += 1
// 				format = formats[idx]
// 			}
// 		}
// 	case .INVALID:
// 		fmt.eprintln("Invalid property type")
// 	}
// }
