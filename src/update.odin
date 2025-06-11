#+private
package main

import "core:thread"
import "core:time"
import "vendor:glfw"
import "core:fmt"
import gl "vendor:OpenGL"

@(private="package")
update_state :: proc(current_time: f64) {
    if do_refresh_buffer_tokens {
        // set_buffer_tokens_threaded()
        do_refresh_buffer_tokens = false
    }
}

@(private="package")
update :: proc(thread: ^thread.Thread) {
    last_time := glfw.GetTime()

    for !glfw.WindowShouldClose(window) {
        current_time := glfw.GetTime()
        local_frame_time := current_time - last_time

        if local_frame_time < target_frame_time {
            sleep_duration := (target_frame_time - local_frame_time) * f64(second)
            time.sleep(time.Duration(sleep_duration))

            continue
        }

        last_time = current_time

        update_state(current_time)
    }
}
