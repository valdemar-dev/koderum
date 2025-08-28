#+private file
package main

import "vendor:glfw"
import "core:strings"
import "core:unicode/utf8"
import "core:math"

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

    runes := utf8.string_to_runes(current_target^)
    
    append_elems(&buf, ..runes)
    append_elem(&buf, key)
    
    delete(current_target^)
    
    current_target^ = utf8.runes_to_string(buf[:])
}

replace_selection :: proc() {
    
}