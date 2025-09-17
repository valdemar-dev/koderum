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
    if is_key_pressed(glfw.KEY_ESCAPE) {
        search_term = strings.clone("")
        replace_text = strings.clone("")
        
        current_target = &search_term
        
        input_mode = .COMMAND
        
        if input_mode_return_callback != nil {
            input_mode_return_callback()
        }
    }
    
    if is_key_pressed(glfw.KEY_BACKSPACE) {
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
    
    if is_key_pressed(glfw.KEY_ENTER) {
        if current_target == &search_term {
            current_target = &replace_text
            
            return
        }
        
        replace_selection()
    }
}

@(private="package")
draw_find_and_replace :: proc() {
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
    
    box_height : f32 = 0
    box_width : f32 = 0
    
    // Calculate Box Size
    title_size := measure_text(normal_text, title)
    box_height += title_size.y
    box_width = max(box_width, title_size.x)
    
    content_size := measure_text(normal_text, content)
    box_height += content_size.y
    box_width = max(box_width, content_size.x)
    
    box := rect{
        0,0,
        box_width,
        box_height,
    }
    
    bg_box := rect{
        box.x - padding,
        box.y - padding,
        box.width - (padding * 2),
        box.height - (padding * 2),
    }
    
    {
        add_rect(&rect_cache, bg_box, no_texture, BG_MAIN_30, vec2{}, z_index-1)
        
        title_pos := vec2{box.x, box.y}
        add_text(&text_rect_cache, title_pos, TEXT_MAIN, normal_text, title, z_index+1)
        
        content_pos := vec2{title_pos.x, title_pos.y + title_size.y}
        add_text(&text_rect_cache, content_pos, TEXT_MAIN, normal_text, content, z_index+1)
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
    
    search_term = strings.clone("")
    replace_text = strings.clone("")
        
    current_target = &search_term
        
    input_mode = .COMMAND
    
    highlight_start_line = -1
    highlight_start_char = -1
}