#+private file
package main

import "core:strings"
import "core:fmt"
import "core:unicode/utf8"
import "vendor:glfw/bindings"

@(private="package")
yank_buffer : SlidingBuffer([50]string)

@(private="package")
generate_highlight_string :: proc(
    start_line: int,
    end_line: int,
    start_char: int,
    end_char: int,
) -> string {
    start_byte_offset := compute_byte_offset(active_buffer, start_line, start_char)
    end_byte_offset := compute_byte_offset(active_buffer, end_line, end_char)
    
    if (start_byte_offset == -1 || end_byte_offset == -1) {
        fmt.println("Failed to compute byte offset in generate_highlight_string due to invalid byte positions.")
        
        return strings.clone("ERR: INVALID_BYTE_POSITION")
    }

    if start_byte_offset > end_byte_offset {
        temp := start_byte_offset

        start_byte_offset = end_byte_offset
        end_byte_offset = temp
    }

    return strings.clone(string(active_buffer.content[start_byte_offset:end_byte_offset]))
}

@(private="package")
copy_to_yank_buffer :: proc(
    start_line: int,
    end_line: int,
    start_char: int,
    end_char: int,
) {
    result := generate_highlight_string(start_line, end_line, start_char, end_char)

    value,did_delete := push(&yank_buffer, result)
    
    if did_delete { delete(value) }
}

@(private="package")
copy_to_clipboard :: proc(
    start_line: int,
    end_line: int,
    start_char: int,
    end_char: int,
) {
    result := generate_highlight_string(start_line, end_line, start_char, end_char)

    cstr := strings.clone_to_cstring(result)
 
    bindings.SetClipboardString(window, cstr)

    delete(result)
}
