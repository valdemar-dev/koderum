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
        normal_text,
        fb_size.x - (margin * 2),
        f32(status_bar_height),
    }

    /*
    status_bar_bg_rect := rect{
        status_bar_rect.x - 15,
        status_bar_rect.y - 10,
        status_bar_rect.width + 30,
        status_bar_rect.height + 20,
    }
    */
    
    line_thickness := math.round_f32(font_base_px * line_thickness_em)

    text_pos := vec2{
        status_bar_rect.x,
        status_bar_rect.y,
    }

    mode_string : string
    mode_bg_color : vec4 = BG_MAIN_10
    mode_text_color : vec4
    
    switch input_mode {
    case .COMMAND:
        mode_string = "Command"
        mode_text_color = TOKEN_COLOR_02
    case .BUFFER_INPUT, .BROWSER_SEARCH, .FILE_CREATE, .FILE_RENAME:
        mode_string = "Text Input"
        mode_text_color = TOKEN_COLOR_00
    case .HIGHLIGHT:
        mode_string = "Highlighting"
        mode_text_color = TOKEN_COLOR_04
    case .SEARCH:
        mode_string = "Search"
        mode_text_color = TOKEN_COLOR_07
    case .DEBUG:
        mode_string = "Debug"
        mode_text_color = TOKEN_COLOR_08
    case .GO_TO_LINE:
        mode_string = "Go To Line"
        mode_text_color = TOKEN_COLOR_09
    case .YANK_HISTORY:
        mode_string = "Yank History"
        mode_text_color = TOKEN_COLOR_05
    }
    
    // Draw Input Mode
    {
        size := add_text_measure(
            &text_rect_cache,
            text_pos,
            mode_text_color,
            normal_text,
            mode_string,
            ui_z_index + 3
        )
        
        padding := small_text / 2
            
        bg_rect := rect{
            text_pos.x - padding * 2,
            text_pos.y - padding,
            size.x + padding * 4,
            size.y + padding * 2,
        }
        
        add_rect(
            &rect_cache,
            bg_rect,
            no_texture,
            mode_bg_color,
            vec2{},
            ui_z_index + 2,
        )
        
        border_rect := rect{
            bg_rect.x - line_thickness,
            bg_rect.y - line_thickness,
            bg_rect.width + line_thickness * 2,
            bg_rect.height + line_thickness * 2,
        }
        
        add_rect(
            &rect_cache,
            border_rect,
            no_texture,
            BG_MAIN_30,
            vec2{},
            ui_z_index + 1,
        )
    }

    // Draw Char History
    if ui_sliding_buffer.count > 0 {
        buf_data_string := utf8.runes_to_string(ui_sliding_buffer.data[:ui_sliding_buffer.count])
        defer delete(buf_data_string)
    
        end_pos := status_bar_rect.x + status_bar_rect.width
    
        buf_data_string_size := measure_text(
            normal_text,
            buf_data_string,
        )
        
        text_pos := vec2{
            end_pos - buf_data_string_size.x,
            status_bar_rect.y
        }
    
        add_text(&text_rect_cache,
            text_pos,
            TEXT_MAIN,
            normal_text,
            buf_data_string,
            ui_z_index + 3,
        )
        
        padding := small_text / 2
        
        bg_rect := rect{
            text_pos.x - padding * 2,
            text_pos.y - padding,
            buf_data_string_size.x + padding * 4,
            buf_data_string_size.y + padding * 2,
        }
        
        add_rect(
            &rect_cache,
            bg_rect,
            no_texture,
            BG_MAIN_10,
            vec2{},
            ui_z_index + 2,
        )
        
        border_rect := rect{
            bg_rect.x - line_thickness,
            bg_rect.y - line_thickness,
            bg_rect.width + line_thickness * 2,
            bg_rect.height + line_thickness * 2,
        }
        
        add_rect(
            &rect_cache,
            border_rect,
            no_texture,
            BG_MAIN_30,
            vec2{},
            ui_z_index + 1,
        )
    }
    
    if active_buffer != nil {
        file_name := active_buffer.info.name

        file_name_size := measure_text(normal_text, file_name)

        half_offset := file_name_size.x / 2
        
        padding : f32 = small_text / 2

        pos := vec2{
            status_bar_rect.x + (status_bar_rect.width / 2) - half_offset,
            status_bar_rect.y,
        }
                
        add_text(&text_rect_cache,
            pos,
            TEXT_MAIN,
            normal_text,
            file_name,
            ui_z_index + 5,
        )


        // Draw Background
        {
            bg_rect := rect{
                pos.x - padding * 2,
                pos.y - padding,
                file_name_size.x + padding * 4,
                file_name_size.y + padding * 2,
            }
            
            add_rect(&rect_cache,
                bg_rect,
                no_texture,
                BG_MAIN_10,
                vec2{},
                ui_z_index + 4,
            )
            
            border_rect := rect{
                bg_rect.x - line_thickness,
                bg_rect.y - line_thickness,
                bg_rect.width + line_thickness * 2,
                bg_rect.height + line_thickness * 2,
            }
            
            add_rect(
                &rect_cache,
                border_rect,
                no_texture,
                BG_MAIN_30,
                vec2{},
                ui_z_index + 3,
            )        
        }
    }
    
    if input_mode == .SEARCH {
        title := "Type to Search"
        
        term_size := measure_text(small_text, buffer_search_term)
        title_size := measure_text(small_text, title)

        padding := small_text
                
        width := max(term_size.x, title_size.x)
        height := term_size.y + title_size.y + padding
        
        middle := fb_size.x / 2 - width / 2
        
        y_pos := fb_size.y - (padding * 2) - 20 - height
        
        // Draw Background
        {
            bg_rect := rect{
                middle - (padding),
                y_pos,
                width + padding * 2,
                height + padding * 2,
            }
            
            line_thickness := math.round_f32(font_base_px * line_thickness_em)
            
            padding_rect := rect{
                bg_rect.x - line_thickness,
                bg_rect.y - line_thickness,
                bg_rect.width + line_thickness * 2,
                bg_rect.height + line_thickness * 2,
            }

            add_rect(&rect_cache,
                bg_rect,
                no_texture,
                BG_MAIN_10,
                vec2{},
                ui_z_index + 3,
            )
            
            add_rect(&rect_cache,
                padding_rect,
                no_texture,
                BG_MAIN_30,
                vec2{},
                ui_z_index + 2,
            )
        }
        
        // Add Content
        {
            add_text(&text_rect_cache,
                vec2{
                    middle,
                    y_pos + padding,
                },
                TEXT_MAIN,
                small_text,
                title,
                ui_z_index + 4,
            )

            add_text(&text_rect_cache,
                vec2{
                    middle,
                    y_pos + padding * 2 + title_size.y,
                },
                TEXT_DARKER,
                small_text,
                buffer_search_term,
                ui_z_index + 4,
            )       
        }
    } else if input_mode == .GO_TO_LINE {
        term := go_to_line_input_string == "" ? "Type a line number." : go_to_line_input_string

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
