package main

import "core:fmt"
import ft "../../alt-odin-freetype"

buffer_cursor_pos := vec2{}
buffer_cursor_target_pos := vec2{}

buffer_cursor_line : int
buffer_cursor_char_index : int

cursor_width : f32
cursor_height : f32

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
            buffer_cursor_pos.x - buffer_horizontal_scroll_position + active_buffer.x_offset,
            buffer_cursor_pos.y - buffer_scroll_position,
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

        if r == '\t' {
            character := get_char(buffer_font_size, u64(' '))

            if character == nil {
                continue
            }

            advance_amount := (character.advance.x / 64) * f32(tab_spaces)

            new_x += advance_amount
            last_width = advance_amount

            continue
        }


        if char == nil {
            char = get_char(buffer_font_size, u64(0))
            
            if char == nil {
                continue
            }
        }

        new_x += (char.advance.x / 64) 
        last_width = (char.advance.x / 64)
    }

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
