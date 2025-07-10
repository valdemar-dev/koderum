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
}

@(private="package")
input_mode : InputMode = .COMMAND

click_pos := Click{}

@(private="package")
key_store : map[i32]ActiveKey = {}

@(private="package")
pressed_chars : [dynamic]rune = {}

@(private="package")
is_key_down :: proc(key: i32) -> bool {
    return key_store[key].is_down
}

@(private="package")
is_key_pressed :: proc(key: i32) -> bool {
    return key_store[key].is_pressed
}

check_inputs :: proc() -> bool {
    #partial switch input_mode {
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
    }

    return false
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

@(private="package")
char_callback :: proc "c" (handle: glfw.WindowHandle, key: rune) {
    context = runtime.default_context()

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
    }
}

@(private="package")
key_callback :: proc "c" (handle: glfw.WindowHandle, key, scancode, action, mods: i32) {
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

    context = runtime.default_context()

    handle_ui_input(key, scancode, action, mods)
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
    if active_buffer == nil {
        return
    }
    
    scroll_target_y = scroll_target_y - f32(scroll_y * 20)
    
    scroll_target_x = max(
        scroll_target_x - f32(scroll_x * 20),
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
    
    /*
    active_buffer.scroll_x = clamp(
        active_buffer.scroll_x,
        -1000,
        0,
    )*/
}

@(private="package")
cursor_callback :: proc "c" (window: glfw.WindowHandle, pos_x,pos_y: f64) {
    mouse_pos = vec2{
        f32(pos_x),
        f32(pos_y),
    }
}

@(private="package")
mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button,action,mods: i32) {
    context = runtime.default_context()
}

handle_command_input :: proc() -> bool {
    if is_key_pressed(glfw.KEY_O) {
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

