package main

import "core:os"
import "core:fmt"
import "core:strings"
import gl "vendor:OpenGL"
import "vendor:glfw"
import "base:runtime"
import "core:unicode/utf8"
import "core:strconv"
import "core:path/filepath"
import ft "../../alt-odin-freetype"

highlight_start_line : int
highlight_start_char : int

@(private="package")
is_not_highlighting :: proc() -> bool {
    if highlight_start_line == 0 && highlight_start_char == 0 do return true
    
    return false
}

@(private="package")
handle_highlight_input :: proc() {
    if is_key_pressed(glfw.KEY_ESCAPE) || is_key_pressed(glfw.KEY_V) {
        input_mode = .COMMAND
        
        highlight_start_line = 0
        highlight_start_char = 0

        return
    } 

    if is_key_pressed(glfw.KEY_Y) {
        key := key_store[glfw.KEY_Y]

        if key.modifiers == 2 {
            copy_to_clipboard(
                highlight_start_line,
                buffer_cursor_line,
                highlight_start_char,
                buffer_cursor_char_index,
            )
        } else {
            copy_to_yank_buffer(
                highlight_start_line,
                buffer_cursor_line,
                highlight_start_char,
                buffer_cursor_char_index,
            )
        }

        return
    }
    
    if is_key_pressed(glfw.KEY_N) {
        set_mode(.GO_TO_LINE, glfw.KEY_N, 'n')
        
        input_mode_return_callback = proc() {
            input_mode = .HIGHLIGHT
        }
        
        return
    }
    
    if is_key_pressed(glfw.KEY_H) {
        set_mode(.FIND_AND_REPLACE, glfw.KEY_H, 'h')
        
        input_mode_return_callback = proc() {
            input_mode = .HIGHLIGHT
        }
    
        return
    }

    if is_key_pressed(glfw.KEY_C) {
        copy_to_yank_buffer(
            highlight_start_line,
            buffer_cursor_line,
            highlight_start_char,
            buffer_cursor_char_index,
        )

        remove_selection(
            highlight_start_line,
            buffer_cursor_line,
            highlight_start_char,
            buffer_cursor_char_index,
        )

        input_mode = .COMMAND
        
        highlight_start_char = 0
        highlight_start_line = 0

        return
    }
    
    if is_key_pressed(glfw.KEY_X) {
        remove_selection(
            highlight_start_line,
            buffer_cursor_line,
            highlight_start_char,
            buffer_cursor_char_index,
        )

        input_mode = .COMMAND
        
        highlight_start_char = 0
        highlight_start_line = 0

        return
    }
    
    if is_key_pressed(glfw.KEY_P) {
        key := key_store[glfw.KEY_P]
        
        
        remove_selection(
            highlight_start_line,
            buffer_cursor_line,
            highlight_start_char,
            buffer_cursor_char_index,
        )
        
        if key.modifiers == CTRL {
            paste_string(glfw.GetClipboardString(window), buffer_cursor_line, buffer_cursor_char_index)        
        } else {
            paste_string(yank_buffer.data[0], buffer_cursor_line, buffer_cursor_char_index)
        }
        
        input_mode = .COMMAND
        
        highlight_start_char = 0
        highlight_start_line = 0
    }

    if is_key_pressed(glfw.KEY_G) {
        buffer_search_term = generate_highlight_string(
            highlight_start_line,
            buffer_cursor_line,
            highlight_start_char,
            buffer_cursor_char_index,
        ) 
    
        set_mode(.SEARCH, glfw.KEY_G, 'g')
        
        highlight_start_line = 0
        highlight_start_char = 0

        find_search_hits()
    }
    
    if is_key_pressed(glfw.KEY_E) {
        indent_selection(
            highlight_start_line,
            buffer_cursor_line,
        )
        
        return
    }
    
    if is_key_pressed(glfw.KEY_W) {
        unindent_selection(
            highlight_start_line,
            buffer_cursor_line,
        )
        
        return
    }

    handle_movement_input()
}
