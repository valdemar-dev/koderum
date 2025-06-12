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
import "core:os"

target_fps :: 240.0
target_frame_time :: 1.0 / target_fps

second := time.Duration(1_000_000_000)

// NOTE:
// this is very silly, but it's fine - val 10th of June 2025.
parse_args :: proc() {
    for arg in os.args {
        if arg == "-save_logs" {
            fmt.println("NOTE: All output will be directed to stdout.txt")
            
            file_handle, err := os.open("stdout.txt", os.O_WRONLY | os.O_CREATE, 0o644)
            if err != os.ERROR_NONE {
                fmt.println("Failed to open file:", os.error_string(err))
                return
            }

            os.stdout = file_handle

            fmt.println("-- START OF LOG --")
        } else if arg == "-log_unhandled_ts" {
            log_unhandled_treesitter_cases = true
        }
    }
}

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
	
    parse_args()
    
    init()

    last_time := glfw.GetTime()

    glfw.SwapBuffers(window)
    
    open_file("/home/v/prog/projects/elegance-js/src/build.ts")

    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents()

        current_time := glfw.GetTime()
        local_frame_time := current_time - last_time

        if local_frame_time < target_frame_time {
            sleep_duration := (target_frame_time - local_frame_time) * f64(second)
            time.sleep(time.Duration(sleep_duration))

            continue
        }
        
        when ODIN_DEBUG {
            fps := 1 / frame_time
            if int(fps) < 60 {
                fmt.println(fps)
            }
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

        when ODIN_OS == .Windows {
            glfw.SwapBuffers(window)
        }

        when ODIN_OS == .Linux {
            if glfw.GetWindowAttrib(window, glfw.VISIBLE) == 1 &&
               glfw.GetWindowAttrib(window, glfw.FOCUSED) == 1
            {
                glfw.SwapBuffers(window)

                continue
            }
        }

    }

    clear_fonts()
    delete_rect_cache(&rect_cache)
    thread.destroy(update_thread)
    reset_rect_cache(&rect_cache)

    delete(default_cwd)
}
