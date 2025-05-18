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
    result : string

    start := start_line
    end := end_line

    is_negative_highlight := start_line >= end_line
    if is_negative_highlight {
        temp := start
        start = end
        end = temp
    }

    for i in start..=end {
        line := active_buffer.lines[i]
        str : string

        if i == start && i == end {
            forward := start_char <= end_char

            if forward {
                str = utf8.runes_to_string(line.characters[start_char:end_char])
            } else {
                str = utf8.runes_to_string(line.characters[end_char:start_char])
            }
        } else if i == end {
            if is_negative_highlight {
                str = utf8.runes_to_string(line.characters[:end_char])
            } else {
                str = utf8.runes_to_string(line.characters[:end_char])
            }
        } else if i == start {
            if is_negative_highlight {
                str = utf8.runes_to_string(line.characters[start_char:])
            } else {
                str = utf8.runes_to_string(line.characters[start_char:])
            }
        } else {
            str = utf8.runes_to_string(line.characters[:])
        }

        result = strings.concatenate({
            result,
            str,
            i != end ? "\n" : "",
        })
    }

    return result
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

   
    bindings.SetClipboardString(window, strings.clone_to_cstring(result))

    delete(result)
}
