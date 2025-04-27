package main

import "core:fmt"
import "vendor:glfw"
import "core:unicode/utf8"
import ft "../../alt-odin-freetype"

ui_general_font_size :: 20
ui_smaller_font_size :: 16

status_bar_rect : rect

ui_sliding_buffer := SlidingBuffer([16]rune){
    length=16,
    data=new([16]rune),
}


@(private="package")
handle_ui_input :: proc(key, scancode, action, mods: i32) {
    if action == glfw.RELEASE {
        return
    }

    key_name := glfw.GetKeyName(key, scancode)

    if mods != 0 {
        push(&ui_sliding_buffer, ' ')
    }

    for r in key_name {
        push(&ui_sliding_buffer, r)
    }

    if mods != 0 {
        value : string

        switch mods {
        case 1:
            value = "S-"
            break
        case 2:
            value = "C-"
        }

        #reverse for r in value {
            push(&ui_sliding_buffer, r)
        }
    }
}

ui_z_index :: 10

draw_ui :: proc() {
    reset_rect_cache(&rect_cache)

    error := ft.set_pixel_sizes(primary_font, 0, u32(ui_general_font_size))
    if error != .Ok do return

    asc := primary_font.size.metrics.ascender >> 6
    desc := primary_font.size.metrics.descender >> 6

    status_bar_height := asc - desc

    one_width_percentage := fb_size.x / 100
    one_height_percentage := fb_size.y / 100

    status_bar_rect = rect{
        one_width_percentage * 20,
        20,
        fb_size.x - (one_width_percentage * 40),
        f32(status_bar_height),
    }

    status_bar_bg_rect := rect{
        status_bar_rect.x - 15,
        status_bar_rect.y - 10,
        status_bar_rect.width + 30,
        status_bar_rect.height + 20,
    }

    add_rect(&rect_cache,
        status_bar_bg_rect,
        no_texture,
        BG_MAIN_20,
        vec2{},
        ui_z_index,
    )

    text_pos := vec2{
        status_bar_rect.x,
        status_bar_rect.y,
    }

    mode_string : string

    switch input_mode {
    case .COMMAND:
        mode_string = "Command"
    case .BUFFER_INPUT, .BROWSER_SEARCH:
        mode_string = "Text Input"
    }

    add_text(&rect_cache,
        text_pos,
        TEXT_MAIN,
        20,
        mode_string,
        ui_z_index + 1
    )

    buf_data_string := utf8.runes_to_string(ui_sliding_buffer.data[:])
    defer delete(buf_data_string)

    end_pos := status_bar_rect.x + status_bar_rect.width

    buf_data_string_size := measure_text(
        ui_general_font_size,
        buf_data_string,
    )

    add_text(&rect_cache,
        vec2{
            end_pos - buf_data_string_size.x,
            status_bar_rect.y
        },
        TEXT_MAIN,
        ui_general_font_size,
        buf_data_string,
        ui_z_index + 1,
    )

    if active_buffer != nil {
        file_name := active_buffer.info.name

        file_name_size := measure_text(ui_general_font_size, file_name)

        half_offset := file_name_size.x / 2

        add_text(&rect_cache,
            vec2{
                status_bar_rect.x + (status_bar_rect.width / 2) - half_offset,
                status_bar_rect.y,
            },
            TEXT_MAIN,
            ui_general_font_size,
            file_name,
            ui_z_index + 1,
        )
    }

    draw_rects(&rect_cache)
}
