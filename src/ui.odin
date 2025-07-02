package main

import "core:fmt"
import "core:math"
import "vendor:glfw"
import "core:unicode/utf8"
import ft "../../alt-odin-freetype"

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
    reset_rect_cache(&text_rect_cache)
    
    normal_text := math.round_f32(font_base_px * normal_text_scale)
    small_text := math.round_f32(font_base_px * small_text_scale)

    error := ft.set_pixel_sizes(primary_font, 0, u32(normal_text))
    if error != .Ok do return

    asc := primary_font.size.metrics.ascender >> 6
    desc := primary_font.size.metrics.descender >> 6

    status_bar_height := asc - desc

    one_width_percentage := fb_size.x / 100
    one_height_percentage := fb_size.y / 100

    margin := one_width_percentage * 10

    status_bar_rect = rect{
        margin,
        20,
        fb_size.x - (margin * 2),
        f32(status_bar_height),
    }

    status_bar_bg_rect := rect{
        status_bar_rect.x - 15,
        status_bar_rect.y - 10,
        status_bar_rect.width + 30,
        status_bar_rect.height + 20,
    }
    
    line_thickness := math.round_f32(font_base_px * line_thickness_em)
    
    {
        border_rect := rect{
            status_bar_bg_rect.x - line_thickness,
            status_bar_bg_rect.y - line_thickness,
            status_bar_bg_rect.width + line_thickness * 2,
            status_bar_bg_rect.height + line_thickness * 2,
        }
        
        add_rect(&rect_cache,
            border_rect,
            no_texture,
            BG_MAIN_30,
            vec2{},
            ui_z_index,
        )
    }

    add_rect(&rect_cache,
        status_bar_bg_rect,
        no_texture,
        BG_MAIN_10,
        vec2{},
        ui_z_index + .1,
    )

    text_pos := vec2{
        status_bar_rect.x,
        status_bar_rect.y,
    }

    mode_string : string

    switch input_mode {
    case .COMMAND:
        mode_string = "Command"
    case .BUFFER_INPUT, .BROWSER_SEARCH, .FILE_CREATE, .FILE_RENAME:
        mode_string = "Text Input"
    case .HIGHLIGHT:
        mode_string = "Highlighting"
    case .SEARCH:
        mode_string = "Search"
    case .DEBUG:
        mode_string = "Debug"
    }

    add_text(&rect_cache,
        text_pos,
        TEXT_MAIN,
        normal_text,
        mode_string,
        ui_z_index + 1
    )

    buf_data_string := utf8.runes_to_string(ui_sliding_buffer.data[:ui_sliding_buffer.count])
    defer delete(buf_data_string)

    end_pos := status_bar_rect.x + status_bar_rect.width

    buf_data_string_size := measure_text(
        normal_text,
        buf_data_string,
    )

    add_text(&rect_cache,
        vec2{
            end_pos - buf_data_string_size.x,
            status_bar_rect.y
        },
        TEXT_MAIN,
        normal_text,
        buf_data_string,
        ui_z_index + 1,
    )

    if active_buffer != nil {
        file_name := active_buffer.info.name

        file_name_size := measure_text(small_text, file_name)

        half_offset := file_name_size.x / 2

        pos := vec2{
            status_bar_rect.x + (status_bar_rect.width / 2) - half_offset,
            status_bar_rect.y,
        }

        padding : f32 : 10

        add_rect(&rect_cache,
            rect{
                pos.x - padding,
                status_bar_bg_rect.y,
                file_name_size.x + padding * 2,
                status_bar_bg_rect.height,
            },
            no_texture,
            BG_MAIN_20,
            vec2{},
            ui_z_index + 2,
        )

        add_text(&rect_cache,
            pos,
            TEXT_MAIN,
            small_text,
            file_name,
            ui_z_index + 3,
        )
    }

    if input_mode == .SEARCH {
        term := buffer_search_term == "" ? "Type to Search" : buffer_search_term

        size := measure_text(normal_text, term)

        middle := fb_size.x / 2 - size.x / 2

        padding :: 10

        add_rect(&rect_cache,
            rect{
                middle - (padding * 1.5),
                fb_size.y - padding - 20 - size.y,
                size.x + padding * 3,
                size.y + padding * 2,
            },
            no_texture,
            BG_MAIN_20,
            vec2{},
            ui_z_index + 3,
        )

        add_text(&text_rect_cache,
            vec2{
                middle,
                fb_size.y - 20 - size.y,
            },
            TEXT_MAIN,
            normal_text,
            term,
            ui_z_index + 4,
        )
    }

    draw_rects(&rect_cache)

    draw_rects(&text_rect_cache)
    reset_rect_cache(&text_rect_cache)
}
