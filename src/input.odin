#+private file
package main

import "vendor:glfw"
import "core:fmt"
import "base:runtime"
import "core:math"

@(private="package")
ActiveKey :: struct {
    is_down: bool,
    is_pressed: bool,
    modifiers: i32,
}

@(private="package")
mouse_pos := vec2{}

last_scroll_direction := 0
Click :: struct {
    button: i32,
    action: i32,
    is_pressed: bool,
    pos: vec2,
}

@(private="package")
InputMode :: enum {
    COMMAND,
    BUFFER_INPUT,
    BROWSER_SEARCH,
    FILE_RENAME,
    FILE_CREATE,
    SEARCH,
    HIGHLIGHT,
    GO_TO_LINE,
    DEBUG,
    YANK_HISTORY,
    TERMINAL,
    TERMINAL_TEXT_INPUT,
    GREP_SEARCH,
    FIND_AND_REPLACE,
    HELP,
}

@(private="package")
input_mode : InputMode = .COMMAND

@(private="package")
input_mode_return_callback : proc() = nil

click_pos := Click{}

@(private="package")
key_store : map[i32]ActiveKey = {}

@(private="package")
pressed_chars : [dynamic]rune = {}

@(private="package")
is_key_down :: proc(key: KEY_CODE) -> bool {
    return key_store[i32(key)].is_down
}

@(private="package")
is_key_pressed :: proc(key: KEY_CODE) -> bool {
    return key_store[i32(key)].is_pressed
}

check_inputs :: proc() -> bool {
    handle_global_input() or_return
    
    #partial switch input_mode {
    case .TERMINAL:
        handle_terminal_control_input() or_return
    case .COMMAND:
        handle_command_input() or_return
    case .BUFFER_INPUT:
        handle_text_input() or_return
    case .BROWSER_SEARCH:
        handle_browser_input()
    case .SEARCH:
        handle_search_input()
    case .GO_TO_LINE:
        handle_go_to_line_input()
    case .HIGHLIGHT:
        handle_highlight_input()
    case .DEBUG:
        handle_debug_input()
    case .YANK_HISTORY:
        handle_yank_history_input()
    case .GREP_SEARCH:
        handle_grep_input()
    case .FIND_AND_REPLACE:
        handle_find_and_replace_input()
    case .HELP:
        handle_help_input()
    }

    return false
}

handle_global_input :: proc() -> (continue_execution: bool = true) {
    if is_key_pressed(glfw.KEY_F11) {
        toggle_fullscreen()
        
        return
    }
    
    if is_key_pressed(glfw.KEY_MINUS) {
        key := key_store[glfw.KEY_MINUS]
        
        if key.modifiers == CTRL_SHIFT {
            font_base_px += 1
        
            continue_execution = false
            
            resize_terminal()
            
            if active_buffer != nil {
                set_buffer_cursor_pos(
                    buffer_cursor_line,
                    buffer_cursor_char_index,
                )
            }
        
            return            
        }
    }
    
    if is_key_pressed(glfw.KEY_SLASH) {
        key := key_store[glfw.KEY_SLASH]
        
        if key.modifiers == CTRL_SHIFT {
            font_base_px = clamp(font_base_px - 1, 4, font_base_px)
            
            continue_execution = false
            
            resize_terminal()
            
            if active_buffer != nil {
                set_buffer_cursor_pos(
                    buffer_cursor_line,
                    buffer_cursor_char_index,
                )
            }
            
            return
        }
        
    }

    
    return continue_execution
}

@(private="package")
process_input :: proc() {
    context = runtime.default_context()

    if is_key_down(glfw.KEY_F10) {
        glfw.SetWindowShouldClose(window, true)
    }

    check_inputs() 

    set_keypress_states()
}

target_key : i32 = -1
char_to_suppress : rune

@(private="package")
set_mode :: proc(mode: InputMode, key: KEY_CODE) {
    input_mode = mode
    
    target_key = i32(key)
    char_to_suppress = rune(key)
    
    glfw.SetKeyCallback(window, key_callback_hijack)
}

key_callback_hijack :: proc "c" (handle: glfw.WindowHandle, key, scancode, action, mods: i32) {
    context = runtime.default_context()
    
    if ((key == target_key) && action == glfw.RELEASE) || target_key == -1{
        target_key = -1
    
        glfw.SetKeyCallback(window, key_callback)
    }
    
    key_callback(handle, key, scancode, action, mods)
}

@(private="package")
char_callback :: proc "c" (handle: glfw.WindowHandle, key: rune) {
    context = runtime.default_context()

    if target_key != -1 && char_to_suppress == key {
        return
    }    

    #partial switch input_mode {
    case .BUFFER_INPUT:
        if is_key_down(glfw.KEY_LEFT_CONTROL) {
            return
        }

        insert_into_buffer(key)

        break
    case .BROWSER_SEARCH:
        browser_append_to_search_term(key)
        break
    case .SEARCH:
        buffer_append_to_search_term(key)
    case .FILE_RENAME:
        break
    case .FILE_CREATE:
        break
    case .GO_TO_LINE:
        append_to_go_to_line_input_string(key)
    case .TERMINAL_TEXT_INPUT:
        handle_terminal_input(key)
    case .GREP_SEARCH:
        grep_append_to_search_term(key)
    case .FIND_AND_REPLACE:
        handle_find_and_replace_text_input(key)
    }
}

@(private="package")
key_callback :: proc "c" (handle: glfw.WindowHandle, key, scancode, action, mods: i32) {
    context = runtime.default_context()
    
    if input_mode == .TERMINAL_TEXT_INPUT {
        do_continue := handle_terminal_emulator_input(key, scancode, action, mods)
        
        if do_continue == false && action == glfw.PRESS {
            return
        }
    }

    handle_ui_input(key, scancode, action, mods)
        
    switch action {
    case glfw.RELEASE:
        key_store[key] = ActiveKey{
            is_down=false,
            is_pressed=false,
            modifiers=mods,
        }

        break
    case glfw.PRESS, glfw.REPEAT: 
        key_store[key] = ActiveKey{
            is_pressed=true,
            is_down=true,
            modifiers=mods,
        }

        break
    }

}

set_keypress_states :: proc() {
    for key, &active_key in key_store {
        active_key = ActiveKey{
            is_down=active_key.is_down,
            is_pressed=false,
            modifiers=active_key.modifiers,
        }
    }
}

@(private="package")
scroll_target_x : f32
@(private="package")
scroll_target_y : f32

@(private="package")
scroll_callback :: proc "c" (handle: glfw.WindowHandle, scroll_x,scroll_y: f64) {
    context = runtime.default_context()
    
    if input_mode == .TERMINAL {
        if scroll_y > 0 {
            scroll_terminal_down(4)
        } else if scroll_y < 0 {
            scroll_terminal_up(4)
        }
        
        return
    }
    
    if active_buffer == nil {
        return
    }
    
    scroll_target_y = scroll_target_y - f32(scroll_y * 40)
    
    scroll_target_x = max(
        scroll_target_x - f32(scroll_x * 40),
        0
    )
}

@(private="package")
tick_smooth_scroll :: proc() {
    if active_buffer == nil {
        return
    }
    
    active_buffer.scroll_x = smooth_lerp(
        active_buffer.scroll_x, 
        scroll_target_x, 
        20,
        frame_time,
    )
    
    active_buffer.scroll_y = smooth_lerp(
        active_buffer.scroll_y, 
        scroll_target_y, 
        20,
        frame_time,
    )
    
    scroll_target_x = max(
        scroll_target_x,
        0
    )
}

is_clicking := false

@(private="package")
cursor_callback :: proc "c" (window: glfw.WindowHandle, pos_x,pos_y: f64) {
    mouse_pos = vec2{
        f32(pos_x),
        f32(pos_y),
    }
    
    context = runtime.default_context()
    
    #partial switch input_mode {
    case .COMMAND:
        if is_clicking == true {
            highlight_start_line = buffer_cursor_line
            highlight_start_char = buffer_cursor_char_index
            
            input_mode = .HIGHLIGHT
            
            buffer_go_to_cursor_pos()
        }
    case .HIGHLIGHT:
        if is_clicking == true {
            buffer_go_to_cursor_pos()
        }
    }
}

@(private="package")
mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button,action,mods: i32) {
    context = runtime.default_context()
    
    if active_buffer == nil {
        return
    }
    
    #partial switch input_mode {
    case .COMMAND:
        if button == glfw.MOUSE_BUTTON_1 {
            if action == glfw.PRESS {
                is_clicking = true
            } else if action == glfw.RELEASE {
                is_clicking = false
                buffer_go_to_cursor_pos()
            }
            
        }
        
        break
    case .HIGHLIGHT:
        if button == glfw.MOUSE_BUTTON_1 {
            if action == glfw.PRESS {
                is_clicking = true
            
                input_mode = .COMMAND
                
                highlight_start_line = -1
                highlight_start_char = -1
            } else if action == glfw.RELEASE {
                is_clicking = false
            }
        }
    }
}

handle_command_input :: proc() -> bool {
    if is_key_pressed(glfw.KEY_F1) {
        toggle_help_menu()
        
        return false
    }
    
    if is_key_pressed(glfw.KEY_F) && is_terminal_open {
        key := key_store[glfw.KEY_F]
        
        if key.modifiers == CTRL {
            input_mode = .TERMINAL
            
            return false
        }
    }
    
    if is_key_pressed(glfw.KEY_T) {
        key := key_store[glfw.KEY_T]
        
        if key.modifiers == CTRL {
            toggle_terminal_emulator()
            
            return false
        }
    }
    
    if is_key_pressed(glfw.KEY_O) {
        key := key_store[glfw.KEY_O]
        
        if key.modifiers == CTRL {
            toggle_grep_view()
            
            return false
        }
        
        toggle_browser_view()

        return false
    }

    if is_key_pressed(glfw.KEY_C) {
        key := key_store[glfw.KEY_C]

        if key.modifiers == CTRL_SHIFT {
            copy_notification_command()
        }
    }

    if is_key_pressed(glfw.KEY_ESCAPE) {
        key := key_store[glfw.KEY_ESCAPE]

        if key.modifiers == CTRL {
            dismiss_notification()
        }
    }

    if is_key_pressed(glfw.KEY_F2) {
        input_mode = .DEBUG
    }


    if active_buffer != nil {
        handle_buffer_input() or_return
    }

    return false
}

