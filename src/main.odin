package main

import "core:fmt"

import gl "vendor:OpenGL"
import "vendor:glfw"
import freetype "../../alt-odin-freetype"
import "core:mem"
import "base:runtime"
import "core:math"
import "core:strings"
import "core:time"
import "core:thread"

target_fps :: 60.0
target_frame_time :: 1.0 / target_fps

second := time.Duration(1_000_000_000)


main :: proc() {
    when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}
	
    init()

    for !glfw.WindowShouldClose(window) {
        process_input()

        set_camera_ui()
        set_view_ui()
        
        tick_buffer_cursor()

        update_camera()
       
        render()

        update_fonts()
    }

    clear_fonts()

    delete_rect_cache(&rect_cache)
}
