package main

import "core:fmt"
import "core:math"
import "core:strings"
import "vendor:glfw"
import "core:unicode/utf8"
import ft "../../alt-odin-freetype"
import fp "core:path/filepath"

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

ui_z_index :: 5000

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
    case .TERMINAL:
        mode_string = "Terminal Control"
        mode_text_color = TOKEN_COLOR_11
    case .TERMINAL_TEXT_INPUT:
        mode_string = "Terminal Text Input"
        mode_text_color = TOKEN_COLOR_11
    case .GREP_SEARCH:
        mode_string = "Grep Search"
        mode_text_color = TOKEN_COLOR_09
    case .FIND_AND_REPLACE:
        mode_string = "Find & Replace"
        mode_text_color = TOKEN_COLOR_10
    case .HELP:
        mode_string = "Help"
        mode_text_color = TOKEN_COLOR_02
    case .VIEW_OPEN_BUFFERS:
        mode_string = "View Open Buffers"
        mode_text_color = TOKEN_COLOR_04
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
    
    // Draw Current File
    if active_buffer != nil {
        /*
            kind of a "name" of the cwd. 
            if we're in /home/user/programming/my-project,
            we assume their "project name" is my-project
        */
        cwd_name := fp.base(cwd)
        
        rel_path, ok := fp.rel(cwd, active_buffer.file_name)
        
        defer delete(rel_path)
        
        file_name := strings.concatenate({
            "\uf07c ", cwd_name, " > ",
            rel_path
        })
        
        defer delete(file_name)
        
        content := active_buffer.is_saved ? file_name : strings.concatenate({ "Unsaved - ", file_name, }, context.temp_allocator)
        
        content_size := measure_text(normal_text, content)

        half_offset := content_size.x / 2
        
        padding : f32 = small_text / 2

        pos := vec2{
            status_bar_rect.x + (status_bar_rect.width / 2) - half_offset,
            status_bar_rect.y,
        }
                
        add_text(&text_rect_cache,
            pos,
            TEXT_MAIN,
            normal_text,
            content,
            ui_z_index + 5,
        )


        // Draw Background
        {
            bg_rect := rect{
                pos.x - padding * 2,
                pos.y - padding,
                content_size.x + padding * 4,
                content_size.y + padding * 2,
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
    
    // Draw GREP
    if input_mode == .SEARCH {
        ui_z_index : f32 = ui_z_index + 10
        
        title := "Type to Search - (Clear: Ctrl + Backspace)"
        
        term_size := measure_text(small_text, buffer_search_term)
        title_size := measure_text(small_text, title)

        padding := small_text
                
        width := max(term_size.x, title_size.x)
        height := term_size.y + title_size.y + padding
        
        middle := fb_size.x / 2 - width / 2
        
        y_pos := fb_size.y - (small_text * 3) - (height + padding * 2)
        
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
                false,
                -1,
                true,
                true,
                -1,
            )       
        }
    } else if input_mode == .GO_TO_LINE {        
        title := "Enter Line Number"
        
        term_size := measure_text(small_text, go_to_line_input_string)
        title_size := measure_text(small_text, title)

        padding := small_text
                
        width := max(term_size.x, title_size.x)
        height := term_size.y + title_size.y + padding
        
        middle := fb_size.x / 2 - width / 2
        
        y_pos := fb_size.y - (small_text * 3) - (height + padding * 2)
        
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
                go_to_line_input_string,
                ui_z_index + 4,
            )       
        }
    }
    
    // Draw Bottom Status Bar
    {
        left_size : vec2
        right_size : vec2
        
        error := ft.set_pixel_sizes(primary_font, 0, u32(small_text))
        if error != .Ok do return
    
        asc := primary_font.size.metrics.ascender >> 6
        desc := primary_font.size.metrics.descender >> 6
        
        font_height := f32(asc - desc)
        
        padding := math.round_f32(font_base_px / 4)
        
        text_y_pos := fb_size.y - font_height - (padding)
        
        // Draw Left
        {
            sb := strings.builder_make()
            
            defer strings.builder_destroy(&sb)
            
            // FPS
            strings.write_string(&sb, "FPS: ")
            strings.write_int(&sb, fps)
            
            when ODIN_DEBUG {
                strings.write_string(&sb, " - Tracked Memory: ")
                strings.write_i64(&sb, track.current_memory_allocated)
            }
            
            left_text := strings.to_string(sb)
            
            left_size = add_text_measure(
                &text_rect_cache,
                vec2{
                    padding,
                    text_y_pos,
                },
                TEXT_DARKER,
                small_text,
                left_text,
                ui_z_index + 5,     
            )
        }
        
        // Draw Right
        {
            width : f32 = 0
            
            sb := strings.builder_make()
            
            defer strings.builder_destroy(&sb)
            
            // Language Server Draw
            if active_buffer != nil && active_buffer.language_server != nil {
                strings.write_string(&sb, "Parser: Yes | ")
                
                if active_buffer.language_server.lsp_server_pid == 0 {
                    strings.write_string(&sb, "LSP: No")
                } else {
                    strings.write_string(&sb, "LSP: Yes")
                    
                    strings.write_string(&sb, " - Diagnostics: ")
                    strings.write_int(&sb, active_buffer.error_count)
                }
            } else {
                strings.write_string(&sb, "Parser: No")
            }
            
            right_text := strings.to_string(sb)
            
            right_size = measure_text(small_text, right_text)
            
            add_text(
                &text_rect_cache,
                vec2{
                    fb_size.x - padding - right_size.x,
                    text_y_pos,
                },
                TEXT_DARKER,
                small_text,
                right_text,
                ui_z_index + 5,     
            )
            
        }
    
        bg_rect := rect{
            0,
            text_y_pos - padding,
            fb_size.x,
            font_height + padding * 2,
        }
        
        add_rect(
            &rect_cache,
            bg_rect,
            no_texture,
            BG_MAIN_00,
            vec2{},
            ui_z_index + 4,
        )
        
        border_rect := rect{
            bg_rect.x,
            bg_rect.y - line_thickness,
            bg_rect.width,
            bg_rect.height + line_thickness * 2,
        }
        
        add_rect(
            &rect_cache,
            border_rect,
            no_texture,
            BG_MAIN_30,
            vec2{},
            ui_z_index + 4,
        )
    }

    draw_rects(&rect_cache)

    draw_rects(&text_rect_cache)
    reset_rect_cache(&text_rect_cache)
}
