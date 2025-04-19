package main

import "core:fmt"

buffer_cursor_pos := vec2{}
buffer_cursor_target_pos := vec2{}

buffer_cursor_line : int
buffer_cursor_char_index : int

cursor_width : f32

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

    cursor_height := buffer_font_size

    add_rect(&rect_cache,
        rect{
            buffer_cursor_pos.x - buffer_horizontal_scroll_position + active_buffer.x_offset,
            buffer_cursor_pos.y - buffer_scroll_position,
            5,
            cursor_height,
        },
        no_texture,
        vec4{1,1,1,1},
    )

    draw_rects(&rect_cache)
}

set_buffer_cursor_pos :: proc(line: int, char_index: int) {
    if active_buffer == nil {
        return
    }

    buffer_lines := active_buffer.lines

    new_line := buffer_lines[line]
    characters := new_line.characters

    new_x : f32 = 0

    last_width : f32 = cursor_width

    buffer_cursor_line = line
    buffer_cursor_char_index = char_index

    for index in 0..<char_index {
        if index >= len(characters) {
            break
        }

        r := characters[index]

        char := get_char(buffer_font_size, u64(r))

        if char == nil {
            continue
        }

        new_x += (char.advance.x / 64) 
        last_width = (char.advance.x / 64)
    }

    cursor_width = last_width

    line_height := buffer_font_size * line_height 

    buffer_cursor_target_pos.x = new_x
    buffer_cursor_target_pos.y = f32(line) * line_height
}

@(private="package")
tick_buffer_cursor :: proc() {
    buffer_cursor_pos.x = smooth_lerp(buffer_cursor_pos.x, buffer_cursor_target_pos.x, 30, frame_time)
    buffer_cursor_pos.y = smooth_lerp(buffer_cursor_pos.y, buffer_cursor_target_pos.y, 30, frame_time)
}
