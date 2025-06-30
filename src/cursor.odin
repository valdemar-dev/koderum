package main

import "core:fmt"
import "core:strings"
import ft "../../alt-odin-freetype"

buffer_cursor_pos := vec2{}
buffer_cursor_target_pos := vec2{}

buffer_cursor_line : int
buffer_cursor_char_index : int
buffer_cursor_desired_char_index : int = -1

cursor_width : f32
cursor_height : f32

has_cursor_moved : bool = false

draw_cursor :: proc() {
    if active_buffer == nil {
        return
    }

    index := character_maps[buffer_font_size]
    char_map := character_maps_array[index]

    if char_map == nil {
        return
    }

    reset_rect_cache(&rect_cache)

    error := ft.set_pixel_sizes(primary_font, 0, u32(buffer_font_size))
    if error != .Ok do return

    asc := primary_font.size.metrics.ascender >> 6
    desc := primary_font.size.metrics.descender >> 6

    cursor_height = f32(asc - desc)

    add_rect(&rect_cache,
        rect{
            buffer_cursor_pos.x - active_buffer.scroll_x + active_buffer.offset_x,
            buffer_cursor_pos.y - active_buffer.scroll_y,
            3,
            cursor_height,
        },
        no_texture,
        vec4{1,1,1,1},
        vec2{},
        3,
    )

    draw_rects(&rect_cache)
}

set_buffer_cursor_pos :: proc(line: int, char_index: int) {
    line := min(line, len(active_buffer.lines)-1)
    char_index := char_index

    if buffer_cursor_desired_char_index != -1 {
        char_index = buffer_cursor_desired_char_index 

        buffer_cursor_desired_char_index = -1
    }
    
    if active_buffer == nil {
        return
    }

    has_cursor_moved = true

    buffer_lines := active_buffer.lines
    
    new_line := buffer_lines[line]
    characters := string(new_line.characters[:])
    new_x : f32 = 0

    last_width : f32 = cursor_width

    char_map := get_char_map(buffer_font_size)

    // looping through a string gives index as byte_index
    rune_index := 0
    for r,byte_index in characters { 
        if rune_index >= char_index {
            break 
        }

        rune_index += 1

        char := get_char_with_char_map(char_map, buffer_font_size, u64(r))

        if r == '\t' {
            character := get_char_with_char_map(char_map, buffer_font_size, u64(' '))

            if character == nil {
                continue
            }

            advance_amount := (character.advance.x) * f32(tab_spaces)

            new_x += advance_amount
            last_width = advance_amount

            continue
        }

        if char == nil {
            continue
        }

        new_x += (char.advance.x) 
        last_width = (char.advance.x)
    }

    if rune_index < char_index && line != buffer_cursor_line {
        buffer_cursor_desired_char_index = char_index
    }

    buffer_cursor_line = line
    buffer_cursor_char_index = rune_index

    cursor_width = last_width

    error := ft.set_pixel_sizes(primary_font, 0, u32(buffer_font_size))
    if error != .Ok do return

    asc := primary_font.size.metrics.ascender >> 6
    desc := primary_font.size.metrics.descender >> 6

    line_height := f32(asc - desc)

    buffer_cursor_target_pos.x = new_x
    buffer_cursor_target_pos.y = f32(line) * line_height
}

@(private="package")
tick_buffer_cursor :: proc() {
    buffer_cursor_pos.x = smooth_lerp(buffer_cursor_pos.x, buffer_cursor_target_pos.x, 30, frame_time)
    buffer_cursor_pos.y = smooth_lerp(buffer_cursor_pos.y, buffer_cursor_target_pos.y, 30, frame_time)
}

@(private="package")
highlighted_error : ^BufferError = nil

error_alert : ^Alert

@(private="package")
get_info_under_cursor :: proc() {
    if active_buffer == nil {
        return
    } 

    line := active_buffer.lines[buffer_cursor_line]

    highlighted_error = nil

    for &error in line.errors {
        start := error.char
        end := error.char + error.width

        if start <= buffer_cursor_char_index && end >= buffer_cursor_char_index {
            highlighted_error = &error

            break
        }
    }

    if highlighted_error == nil {
        if error_alert != nil {
            dismiss_alert()
    
            error_alert = nil
        }
        
        return
    }

    if error_alert == nil {
        error_alert = new(Alert)

        error_alert^.show_seconds = -1
        error_alert^.allocator = context.allocator

        append(&alert_queue, error_alert)
    } else {
        delete(error_alert.title)
        delete(error_alert.content)
    }

    switch highlighted_error.severity {
    case 1:
        error_alert^.title = strings.clone("Error:")
    case 2:
        error_alert^.title = strings.clone("Warning:")
    case 3:
        error_alert^.title = strings.clone("Info:")
    case 4:
        error_alert^.title = strings.clone("Hint:")
    }

    error_alert^.content = strings.clone(highlighted_error.message)
}



