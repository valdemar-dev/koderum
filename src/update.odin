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
import "core:sort"
import "core:net"

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

    if has_cursor_moved {
        get_info_under_cursor()

        has_cursor_moved = false
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
            return
        }
        
        if active_language_server.lsp_server_pid == 0 {
            return
        }

        last_time = current_time

        bytes, read_err := read_lsp_message(
            active_language_server.lsp_stdout_r,
            context.allocator,
        )

        defer delete(bytes)

        if read_err == os.ERROR_EOF {
            return
        }
        
        if read_err != os2.ERROR_NONE {
            fmt.println(read_err)
            panic("Failed to read LSP Message.")
        }

        parsed,_ := json.parse(bytes)
        defer json.destroy_value(parsed)

        obj, ok := parsed.(json.Object)

        if !ok {
            fmt.println(string(bytes))
            
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

        when ODIN_DEBUG {
            fmt.println("Received Notification: ",parsed)
        }

        process_lsp_notification(obj)
    }
}

process_lsp_notification :: proc (parsed: json.Object) {
    method, ok := parsed["method"].(json.String)

    if !ok {
        return
    }

    if method == "textDocument/publishDiagnostics" {
        params := parsed["params"].(json.Object)

        errors, ok := params["diagnostics"].(json.Array)
        uri, _ := params["uri"].(json.String)

        url := uri[7:]
        decoded, decoded_ok := net.percent_decode(url)

        buffer := get_buffer_by_name(decoded)
        
        if buffer == nil {
            // lsp can set diagnostics for files that aren't open.
            return
        }

        if !ok {
            panic("Malformed diagnostics array in textDocumentation/publishDiagnostics.")
        }

        set_lsp_diagnostics(errors, buffer)
    }
}

set_lsp_diagnostics :: proc(errors: json.Array, buffer: ^Buffer) {
    sort_proc :: proc(error_a, error_b: json.Value) -> int {
        error_obj, ok := error_a.(json.Object)

        if !ok {
            panic("Cannot sort invalid JSON object in set_lsp_diagnostics.")
        }

        range_a := error_obj["range"].(json.Object)
        range_b := error_obj["range"].(json.Object)

        start_a := range_a["start"].(json.Object)
        start_line_a := start_a["line"].(json.Float)
        start_char_a := start_a["character"].(json.Float)

        start_b := range_b["start"].(json.Object)
        start_line_b := start_b["line"].(json.Float)
        start_char_b := start_b["character"].(json.Float)

        if start_line_a == start_line_b {
            if start_char_a == start_char_b {
                end_a := range_a["end"].(json.Object)
                end_line_a := end_a["line"].(json.Float)
                end_char_a := end_a["character"].(json.Float)

                end_b := range_b["end"].(json.Object)
                end_line_b := end_b["line"].(json.Float)
                end_char_b := end_b["character"].(json.Float)

                if end_line_a == end_line_b {
                    return int(end_char_a - end_char_b)
                }

                return int(end_line_a - end_char_b)
            }

            return int(start_char_a - start_char_b)
        }

        return int(start_line_a - start_line_b)
    }
    
    for &line in buffer.lines {
        for error in line.errors {
            delete(error.source)
            delete(error.message)
        }

        clear(&line.errors)
    }
    
    buffer^.error_count = len(errors)
    if len(errors) == 0 do return
    
    sort.quick_sort_proc(errors[:], sort_proc)

    for error in errors {
        error_obj, ok := error.(json.Object)

        if !ok {
            fmt.eprintln("ERROR: Badly formed error in LSP diagnostics.", error)

            continue
        }

        range := error_obj["range"].(json.Object)

        start := range["start"].(json.Object)
        start_line := start["line"].(json.Float)
        start_char := start["character"].(json.Float)

        end := range["end"].(json.Object)
        end_line := end["line"].(json.Float)
        end_char := end["character"].(json.Float)

        message := error_obj["message"].(json.String)

        source, source_ok := error_obj["source"].(json.String)

        severity := error_obj["severity"].(json.Float)

        if start_line == end_line {
            if int(start_line) >= len(buffer.lines) {
                // used to print, safer to just ignore.
                // can be due to poor LSP handling.
                // fmt.println("A BUFFER ERROR WAS OUT OF BOUNDS: ", error_obj)

                continue
            }

            buf_line := &buffer.lines[int(start_line)]

            error := BufferError{
                severity=int(severity),
                message=strings.clone(message),
            }

            if source_ok do error.source=strings.clone(source)

            error.char = int(start_char)
            error.width = int(end_char - start_char)

            append(&buf_line.errors, error)

            continue
        }

        for cur_line in start_line..=end_line {
            if int(cur_line) >= len(buffer.lines) {
                //fmt.println("A BUFFER ERROR WAS OUT OF BOUNDS: ", error_obj)

                continue
            }

            buf_line := &buffer.lines[int(cur_line)]

            error := BufferError{
                message=strings.clone(message),
                severity=int(severity),
            }

            if source_ok do error.source=strings.clone(source)

            if cur_line == start_line { 
                error.char = int(start_char)

                count := strings.rune_count(
                    string(buf_line.characters[:]),
                )

                error.width = count - error.char
            } else if cur_line == end_line {
                error.char = 0
                error.width = error.char
            } else {
                count := strings.rune_count(
                    string(buf_line.characters[:]),
                )

                error.width = count
            }

            /*
               WARNING: Design impl flaw.
               Idk how to do multi line tokens in a goodly way.
               So, we're doing this.
            */
            clear(&buf_line.errors)
            append(&buf_line.errors, error)
        }
    }
}

@(private="package")
send_lsp_message :: proc(
    content: string,
    id: string,
    response_proc: proc(response: json.Object, data: rawptr) = nil,
    data: rawptr = nil,
) {
    if active_language_server == nil {
        return
    }
    
    if active_language_server.lsp_server_pid == 0 {
        return
    }
    
    status, _ := os2.process_wait(active_language_server.lsp_server_process, 0)
    if status.exited == true {
        handle_lsp_crash(active_language_server)
        
        return
    }

    os2.write(active_language_server.lsp_stdin_w, transmute([]u8)content)

    when ODIN_DEBUG {
        fmt.println("LSP Message: Adding a message with ID", id)
    }
    
    // fmt.println(content)
    
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
update_thread_allocator : mem.Allocator

@(private="package")
update :: proc(thread: ^thread.Thread) {
    last_time := glfw.GetTime()

    context.allocator = update_thread_allocator

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
