#+private
package main

import "core:thread"
import "core:time"
import "vendor:glfw"
import "core:fmt"
import gl "vendor:OpenGL"
import "core:encoding/json"
import "core:os/os2"
import "core:os"
import "core:strings"
import "core:mem"

LSPRequest :: struct {
    id: string,
    response_proc: proc(response: json.Object, data: rawptr),
    data: rawptr,
}

@(private="package")
requests : [dynamic]LSPRequest

@(private="package")
update_state :: proc(current_time: f64) {
    if do_refresh_buffer_tokens {
        set_buffer_tokens_threaded()
    }
}

@(private="package")
message_loop :: proc(thread: ^thread.Thread) {
    last_time := glfw.GetTime()

    for !glfw.WindowShouldClose(window) {
        current_time := glfw.GetTime()
        local_frame_time := current_time - last_time

        if local_frame_time < target_frame_time {
            sleep_duration := (target_frame_time - local_frame_time) * f64(second)
            time.sleep(time.Duration(sleep_duration))

            continue
        }

        if active_language_server == nil {
            continue
        }

        last_time = current_time

        bytes, read_err := read_lsp_message(
            active_language_server.lsp_stdout_r,
            context.allocator,
        )

        defer delete(bytes)

        if read_err != os2.ERROR_NONE {
            fmt.println(read_err)
            panic("Failed to read LSP Message.")
        }

        parsed,_ := json.parse(bytes)
        defer json.destroy_value(parsed)

        obj, ok := parsed.(json.Object)

        if !ok {
            panic("Malformed LSP JSON.")
        }

        id_value := &obj["id"]

        if id_value != nil {
            id, ok := id_value^.(string)

            when ODIN_DEBUG {
                fmt.println("LSP Message Loop: Processing Request Response with ID", id)
            }

            for &request,index in requests {
                if request.id == id {
                    delete(request.id)

                    request.response_proc(obj, request.data)
                    
                    unordered_remove(&requests, index)

                    break
                }
            }

            continue
        } 

        fmt.println("Received Notification: ",parsed)

    }
}

@(private="package")
send_lsp_message :: proc(
    content: string,
    id: string,
    response_proc: proc(response: json.Object, data: rawptr) = nil,
    data: rawptr = nil,
) {
    os2.write(active_language_server.lsp_stdin_w, transmute([]u8)content)

    when ODIN_DEBUG {
        fmt.println("LSP Message: Adding a message with ID", id)
    }

    if id == "" {
        return
    }

    append(&requests, LSPRequest{
        data=data,
        id=strings.clone(id),
        response_proc=response_proc,
    })
}

@(private="package")
send_lsp_init_message :: proc(
    content: string,
    fd: ^os2.File,
) {
    _, write_err := os2.write(fd, transmute([]u8)content)

    when ODIN_DEBUG {
        fmt.println("LSP Message: Sent an initilization request.",)
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
