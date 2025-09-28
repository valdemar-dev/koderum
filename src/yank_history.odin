#+private file
package main

import "core:math"
import "core:fmt"
import "vendor:glfw"
import "core:strconv"
import "core:strings"

suppress := true
do_show := false

x_pos : f32 = 0
last_width : f32 = 300

selected_index : int = 0

@(private="package")
show_yank_history :: proc() {
    suppress = false
    do_show = true
    
    input_mode = .YANK_HISTORY
    
    selected_index = 0
}

hide_yank_history :: proc() {
    do_show = false
    
    input_mode = .COMMAND
}

@(private="package")
draw_yank_history :: proc() {
    if suppress do return
    
    pen := vec2{ x_pos, font_base_px * 5 }
    
    start_pen := pen
    
    small_text := math.round_f32(font_base_px * small_text_scale)
    normal_text := math.round_f32(font_base_px * normal_text_scale)
    
    line_thickness := math.round_f32(font_base_px * line_thickness_em)
    
    padding := small_text
    
    reset_rect_cache(&rect_cache)
    reset_rect_cache(&text_rect_cache)
    
    gap := small_text * .5
    
    {
        size := add_text_measure(
            &text_rect_cache,
            pen,
            TEXT_MAIN,
            normal_text,
            "Yank History",
            ui_z_index + 2,
            true,
            300,
            false,
            true,
        )
        
        pen.y += size.y + gap
    }
    
    if yank_buffer.count == 0 {
        size := add_text_measure(
            &text_rect_cache,
            pen,
            TEXT_DARKER,
            small_text,
            "Nothing yanked yet.",
            ui_z_index + 2,
            true,
            300,
            false,
            true,
        )
        
        pen.y += size.y
    }
    
    for i in selected_index..<yank_buffer.count {
        hit := yank_buffer.data[i]
        
        if hit == "" {
            break
        }
        
        // Divider
        if i != selected_index {
            pen.y += gap
            
            divider := rect{
                pen.x,
                pen.y,
                last_width,
                line_thickness,
            }
            
            add_rect(&rect_cache, divider, no_texture, BG_MAIN_30, vec2{}, ui_z_index+1)
            
            pen.y += gap
        }
        
    	buf: [4]byte
    	result := strconv.itoa(buf[:], i+1)
        
        size := add_text_measure(
            &text_rect_cache,
            pen,
            TEXT_DARKER,
            small_text,
            strings.concatenate({ result, ":", hit, }, context.temp_allocator),
            ui_z_index + 2,
            true,
            300,
            false,
            true,
        )
        
        pen.y += size.y
    }
    
    // Draw Background
    {
        bg_rect := rect{
            start_pen.x - padding,
            start_pen.y - padding,
            last_width + padding * 2,
            pen.y - start_pen.y + padding * 2,
        }
        
        border_rect := rect{
            bg_rect.x - line_thickness,
            bg_rect.y - line_thickness,
            bg_rect.width + (line_thickness * 2),
            bg_rect.height + (line_thickness * 2),
        }
        
        add_rect(&rect_cache, bg_rect, no_texture, BG_MAIN_10, vec2{}, ui_z_index+1)
        add_rect(&rect_cache, border_rect, no_texture, BG_MAIN_30, vec2{}, ui_z_index)
    }
    
    draw_rects(&rect_cache)
    draw_rects(&text_rect_cache)
}

@(private="package")
tick_yank_history :: proc() {
    if suppress {
        x_pos = fb_size.x
        
        return
    }
    
    padding := math.round_f32(font_base_px * small_text_scale)
    
    if do_show {
        x_pos = smooth_lerp(x_pos, fb_size.x - last_width - (padding * 2), 100, frame_time)
    } else {
        x_pos = smooth_lerp(x_pos, fb_size.x, 100, frame_time)
        
        if int(x_pos) >= int(fb_size.x - 5) {
            suppress = true
            
            selected_index = 0
        }
    }
}

@(private="package")
handle_yank_history_input :: proc() {
    if is_key_pressed(mapped_keybinds[.TOGGLE_YANK_HISTORY_MODE]) {
        hide_yank_history()
        
        return
    }
    
    if is_key_pressed(mapped_keybinds[.ENTER]) {        
        if yank_buffer.count == 0 {
            return
        }
        
        push(&yank_buffer, yank_buffer.data[selected_index])
        
        hide_yank_history()
        
        return
    }
    
    if is_key_pressed(mapped_keybinds[.MOVE_DOWN]) {
        if yank_buffer.count == 0 do return
        
        selected_index = clamp(
            selected_index + 1,
            0,
            yank_buffer.count - 1,
        )
        
        return
    }
    
    if is_key_pressed(mapped_keybinds[.MOVE_UP]) {
        if yank_buffer.count == 0 do return
        
        selected_index = clamp(
            selected_index - 1,
            0,
            yank_buffer.count - 1,
        )
        
        return
    }
}