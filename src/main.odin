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

target_fps :: 144.0
target_frame_time :: 1.0 / target_fps
target_fps_measurement_time :: 1.0

fps : int

second := time.Duration(1_000_000_000)

do_print_frame_time : bool

@(private="file")
fullscreen : bool = false
@(private="file")
stored_width : i32
@(private="file")
stored_height : i32
@(private="file")
stored_pos_x : i32
@(private="file")
stored_pos_y : i32

toggle_fullscreen :: proc() {
    if !fullscreen {
        stored_pos_x, stored_pos_y = glfw.GetWindowPos(window)
        stored_width, stored_height = glfw.GetWindowSize(window)

        monitor := glfw.GetPrimaryMonitor()
        video_mode := glfw.GetVideoMode(monitor)

        glfw.SetWindowMonitor(window, monitor,
                              0, 0,
                              video_mode.width, video_mode.height,
                              video_mode.refresh_rate)
    } else {
        glfw.SetWindowMonitor(window, nil,
                              stored_pos_x, stored_pos_y,
                              stored_width, stored_height,
                              0)
    }

    fullscreen = !fullscreen
}


parse_args :: proc() {
    print_help :: proc() {
        fmt.println("Available Options:")
        
        fmt.println("-save_logs", "Pipes stdout to stdout.txt, (relative to executable path)")
        fmt.println("-log_unhandled_ts", "Writes captured, yet uncolored tree-sitter named nodes to stdout.")
        fmt.println("-print_frame_time", "Writes frame times to stdout.")
        fmt.println("-terminal_debug_mode", "Writes verbose TTY information to stdout.")
        
        os.exit(0)
    }
    
    for arg in os.args[1:] {
        switch arg {
        case "-help":
            print_help()
            break
        case "-log_unhandled_ts":
            log_unhandled_treesitter_cases = true
            break
        case "-print_frame_time":
            do_print_frame_time = true
            break
        case "-terminal_debug_mode":
            terminal_debug_mode = true
            break
        case "-save_logs":
            fmt.println("NOTE: All output will be directed to stdout.txt")

            file_handle, err := os.open("koderum.log", os.O_WRONLY | os.O_CREATE, 0o644)
            if err != os.ERROR_NONE {
                fmt.println("Failed to open file:", os.error_string(err))
                return
            }

            os.stdout = file_handle

            fmt.println("-- START OF LOG --")
            break
        case: 
            fmt.println("Unknown option:", arg)
            print_help()
            break
        }
    }
}

track: mem.Tracking_Allocator
global_context: runtime.Context

cleanup_procedures : [dynamic]proc()

main :: proc() {
    fmt.println("Loading..")
    
    file_handle, err := os.open("error.json", os.O_WRONLY | os.O_CREATE, 0o644)
    
    if err == os.ERROR_NONE {
        fmt.println("Piping errors to error.json!")
        os.stderr = file_handle
    }
    
    when ODIN_DEBUG {
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

    global_context = context

    parse_args()
    
    init()
    resize_terminal()
    update_fonts()
    resize_terminal()

    thread.run(discord)
    
    last_time := glfw.GetTime()
    last_fps_measurement_time := glfw.GetTime()

    glfw.SwapBuffers(window)

    for !glfw.WindowShouldClose(window) {
        current_time := glfw.GetTime()
        local_frame_time := current_time - last_time
        local_fps_measurement_time := current_time - last_fps_measurement_time

        if local_frame_time < target_frame_time {
            time.sleep(time.Duration((target_frame_time - local_frame_time) * f64(time.Second)))
            
            continue
        }
        
        if local_fps_measurement_time >= target_fps_measurement_time {
            last_fps_measurement_time = current_time
            
            fps = int(1 / frame_time)
        }

        if do_print_frame_time do fmt.println(frame_time)
        
        last_time = current_time

        process_input()

        set_camera_ui()
        set_view_ui()

        // these are mostly animations
        {
            tick_buffer_cursor()
            tick_buffer_info_view()
            tick_browser_view()
            tick_grep_view()
            tick_notifications()
            tick_alerts()
            tick_help()
            tick_smooth_scroll()
            tick_yank_history()
            tick_terminal_emulator()
            tick_find_and_replace()
        }
        
        update_fonts()
        update_camera()
 
        render()

        free_all(context.temp_allocator)
        cleanup()
        
        glfw.PollEvents()

        when ODIN_OS == .Windows {
            glfw.SwapBuffers(window)
        }
        
        if (glfw.GetWindowAttrib(window, glfw.FOCUSED) == 0) {
            glfw.SwapInterval(0)
        } else {
            glfw.SwapInterval(1)
        }

        if glfw.GetWindowAttrib(window, glfw.VISIBLE) == 1 {
            glfw.SwapBuffers(window)

            continue
        }
    }

    clear_fonts()

    delete_rect_cache(&rect_cache)
    delete_rect_cache(&text_rect_cache)

    thread.terminate(update_thread, 9)
    thread.terminate(message_thread, 9)

    thread.destroy(update_thread)
    thread.destroy(message_thread)

    reset_rect_cache(&rect_cache)
    
    reset_completion_hits()
    delete(completion_hits)
       
    for key, server in active_language_servers {
        for type in server.token_types {
            delete(type)
        }
        
        for mod in server.token_modifiers {
            delete(mod)
        }
        
        delete(server.completion_trigger_runes)
        delete(server.token_types)
        delete(server.token_modifiers)
    }
    
    for notification in notification_queue {
        delete(notification.title)
        delete(notification.content)
        delete(notification.copy_text)
        
        free(notification)
    }
    
    delete(notification_queue)
        
    for buffer in buffers {
        for &line in buffer.lines {
            clean_line(&line)
        }

        delete(buffer.content)
        delete(buffer.lines^)
    }

    for dir in search_ignored_dirs {
        delete(dir)
    }

    delete(default_cwd)
    delete(font_list)
    delete(delimiter_runes)
    delete(search_ignored_dirs)
    delete(buffers)
    
    delete(program_dir)
    
    delete(active_language_servers)
    
    for request in requests {
        fmt.println("Cleanup: LSP did not respond to request with ID: ", request.id)
        
        fmt.println("Proc:", request.response_proc)
        
        delete(request.id)
    }

    delete(requests)
    
    delete(data_dir)
    delete(config_dir)
    
    {
        for alert in alert_queue {
            delete(alert.title, alert.allocator)
            delete(alert.content, alert.allocator)
    
            free(alert, alert.allocator)
        }
        clear(&alert_queue)
    }
    
    for cleanup_proc in cleanup_procedures {
        cleanup_proc()
    }
}

cleanup :: proc() {
    if lsp_request_id > 5000 {
        lsp_request_id = 10
    }
}
