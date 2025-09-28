#+private file
package main

import "vendor:glfw"
import "core:strings"
import "core:unicode/utf8"
import "core:math"
import "core:fmt"

search_term: string
replace_text: string

current_target := &search_term

@(private="package")
handle_find_and_replace_input :: proc() {
    if is_key_pressed(mapped_keybinds[.ESCAPE]) {
        hide_find_and_replace()
        
        if input_mode_return_callback != nil {
            input_mode_return_callback()
        }
    }
    
    if is_key_pressed(mapped_keybinds[.ESCAPE]) {
        if len(current_target^) == 0 {
            return
        }
        
        runes := utf8.string_to_runes(current_target^)
        defer delete(runes)
        
        runes = runes[:len(runes)-1]
        
        delete(current_target^)
        current_target^ = utf8.runes_to_string(runes)
    
        return
    }
    
    if is_key_pressed(mapped_keybinds[.ENTER]) {
        if current_target == &search_term {
            current_target = &replace_text
            
            return
        }
        
        replace_selection()
    }
}

suppress := true
do_show := false

x_pos : f32 = 0
last_width : f32 = 0

@(private="package")
show_find_and_replace :: proc() {
    suppress = false
    do_show = true
    
    set_mode(.FIND_AND_REPLACE, mapped_keybinds[.ENTER_FIND_AND_REPLACE_MODE])
}

hide_find_and_replace :: proc() {
    search_term = strings.clone("")
    replace_text = strings.clone("")
    
    current_target = &search_term
    
    input_mode = .COMMAND
    
    do_show = false
}

@(private="package")
tick_find_and_replace :: proc() {
    if suppress {
        x_pos = 0 - last_width
        
        return
    }
    
    padding := math.round_f32(font_base_px * small_text_scale)
    
    if do_show {
        x_pos = smooth_lerp(x_pos, (padding * 2), 100, frame_time)
    } else {
        x_pos = smooth_lerp(x_pos, 0 - last_width, 100, frame_time)
        
        if int(x_pos) >= int(fb_size.x - 5) {
            suppress = true
        }
    }
}

@(private="package")
draw_find_and_replace :: proc() {
    if suppress do return
    
    title : string
    content := current_target^
    
    if current_target == &search_term {
        title = "Enter a Search Term:"
    } else if current_target == &replace_text {
        title = "Enter Replace Text:"
    }
    
    reset_rect_cache(&rect_cache)
    reset_rect_cache(&text_rect_cache)
    
    defer draw_rects(&text_rect_cache)
    defer draw_rects(&rect_cache)
    
    z_index : f32 = ui_z_index
    
    normal_text := math.round_f32(font_base_px * normal_text_scale)
    small_text := math.round_f32(font_base_px * small_text_scale)
    
    padding := math.round_f32(font_base_px * small_text_scale)
    line_thickness := math.round_f32(font_base_px * line_thickness_em)
    
    box_height : f32 = 0
    box_width : f32 = 0
    
    box := rect{x_pos, font_base_px * 5, 0,0}

    pen_y := box.y
    
    // Add Title
    {
        size := add_text_measure(
            &text_rect_cache,
            vec2{box.x, box.y},
            TEXT_MAIN,
            normal_text,
            title,
            z_index +1,
        )
        
        box_width = max(box_width, size.x)
        pen_y += size.y + size.y / 2
    }
    
    // Add Content
    {
        size := add_text_measure(
            &text_rect_cache,
            vec2{box.x, pen_y},
            TEXT_MAIN,
            normal_text,
            content,
            z_index +1,
        )
        
        add_rect(&text_rect_cache,
            rect{
                box.x + size.x,
                pen_y,
                cursor_width,
                size.y
            },
            no_texture,
            TEXT_MAIN,
            vec2{},
            z_index + 2,
        )
        
        box_width = max(box_width, size.x)
        pen_y += size.y        
    }
    
    {
        box_height = pen_y - box.y
        
        box.width = box_width + padding * 2
        box.height = box_height + padding * 2
        
        // shift by padding to create padding
        box.x -= padding
        box.y -= padding
        
        last_width = box.width
    }
    
    bg_box := rect{
        box.x - line_thickness,
        box.y - line_thickness,
        box.width + (line_thickness * 2),
        box.height + (line_thickness * 2),
    }
    
    
    // Draw Box
    {
        add_rect(&rect_cache,
            box,
            no_texture,
            BG_MAIN_10,
            vec2{},
            z_index,
        )
        
        add_rect(&rect_cache,
            bg_box,
            no_texture,
            BG_MAIN_30,
            vec2{},
            z_index - 1,
        )
    }
    
    return
}

@(private="package")
handle_find_and_replace_text_input :: proc(key: rune) {
    buf := make([dynamic]rune)
    defer delete(buf)

    runes := utf8.string_to_runes(current_target^)
    
    append_elems(&buf, ..runes)
    append_elem(&buf, key)
    
    delete(current_target^)
    current_target^ = utf8.runes_to_string(buf[:])
}

replace_selection :: proc() {
    context = global_context
    
    start_line, start_char := highlight_start_line, highlight_start_char
    end_line, end_char := buffer_cursor_line, buffer_cursor_char_index
    
    if end_line < start_line {
        temp_line := start_line
        temp_char := start_char
        
        start_line = end_line
        start_char = end_char
        
        end_line = temp_line
        end_char = temp_char
    }
    
    selection := generate_highlight_string(
        start_line,
        end_line,
        start_char,
        end_char,
    )
    
    new_content := string_replace(selection, search_term, replace_text)
    
    // Update Buffer
    {
        hl_start_byte := compute_byte_offset(
            active_buffer,
            start_line,
            start_char,
        )
        
        hl_end_byte := compute_byte_offset(
            active_buffer,
            end_line,
            end_char,
        )
        
        end, end_byte := byte_to_pos(u32(hl_start_byte + len(selection)))
        end_rune := byte_offset_to_rune_index(
            string(active_buffer.lines[end].characters[:]),
            int(end_byte),
        )
    
        remove_range(&active_buffer.content, hl_start_byte, hl_start_byte + len(selection))
        inject_at(&active_buffer.content, hl_start_byte, ..transmute([]u8)new_content)
        
        change := BufferChange{
            u32(hl_start_byte),
            u32(hl_end_byte),
            
            start_line,
            start_char,
            
            end_line,
            end_char,
            
            transmute([]u8)selection,
            transmute([]u8)new_content,
            
            0,
            0,
        }
        
        append(&active_buffer.undo_stack, change)
        reset_change_stack(&active_buffer.redo_stack)
        
        update_buffer_lines_after_change(active_buffer, change, false)
        
        notify_server_of_change(
            active_buffer,
            hl_start_byte,
            hl_start_byte + len(selection),
            start_line,
            start_char,
            end,
            end_rune,
            transmute([]u8)new_content,
            false,
        )
    }
    
    hide_find_and_replace()
    
    highlight_start_line = -1
    highlight_start_char = -1
}