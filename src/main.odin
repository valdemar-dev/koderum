package main

import "core:fmt"

import gl "vendor:OpenGL"
import freetype "../../alt-odin-freetype"

import "vendor:glfw"
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
    fmt.println("Loading..")

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

    last_time := glfw.GetTime()

    glfw.SwapBuffers(window)

    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents()

        current_time := glfw.GetTime()
        local_frame_time := current_time - last_time

        if local_frame_time < target_frame_time {
            sleep_duration := (target_frame_time - local_frame_time) * f64(second)
            time.sleep(time.Duration(sleep_duration))

            continue
        }

        last_time = current_time

        process_input()

        set_camera_ui()
        set_view_ui()
        
        tick_buffer_cursor()
        tick_buffer_info_view()
        tick_browser_view()

        update_camera()

        update_fonts()
 
        render()

        free_all(context.temp_allocator)

        if glfw.GetWindowAttrib(window, glfw.VISIBLE) == 1 &&
           glfw.GetWindowAttrib(window, glfw.FOCUSED) == 1
        {
            glfw.SwapBuffers(window)

            continue
        }
    }

    clear_fonts()
    delete_rect_cache(&rect_cache)
    thread.destroy(update_thread)
    reset_rect_cache(&rect_cache)

    delete(default_cwd)
}
