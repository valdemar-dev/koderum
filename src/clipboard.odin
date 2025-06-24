#+private file
package main

import "core:strings"
import "core:fmt"
import "core:unicode/utf8"
import "vendor:glfw/bindings"

@(private="package")
yank_buffer := SlidingBuffer([50]string){
    length=50,
    data=new([50]string)
}

@(private="package")
generate_highlight_string :: proc(
    start_line: int,
    end_line: int,
    start_char: int,
    end_char: int,
) -> string {
    start_byte_offset := compute_byte_offset(active_buffer, start_line, start_char)
    end_byte_offset := compute_byte_offset(active_buffer, end_line, end_char)

    if start_byte_offset > end_byte_offset {
        temp := start_byte_offset

        start_byte_offset = end_byte_offset
        end_byte_offset = temp
    }

    return strings.clone(string(active_buffer.content[start_byte_offset:end_byte_offset]))
    /*

    start_buffer_line := active_buffer.lines[start_line]
    start_offset := utf8.rune_offset(string(start_buffer_line.characters[:]), start_char)
    if start_offset == -1 {
        start_offset = len(start_buffer_line.characters[:])
    }

    append(&result, ..start_buffer_line.characters[:start_offset])

    for i in start_line..<end_line {
        line := active_buffer.lines[i]

        append(&result, ..line.characters[:])
        append(&result, u8('\n'))
    }

    end_buffer_line := active_buffer.lines[end_line]

    end_offset := utf8.rune_offset(string(end_buffer_line.characters[:]), end_char)
    if end_offset == -1 {
        end_offset = len(end_buffer_line.characters[:])
    }

    append(&result, ..end_buffer_line.characters[:end_char])

    return string(result[:])
    */
}

@(private="package")
copy_to_yank_buffer :: proc(
    start_line: int,
    end_line: int,
    start_char: int,
    end_char: int,
) {
    result := generate_highlight_string(start_line, end_line, start_char, end_char)

    push(&yank_buffer, result)
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
