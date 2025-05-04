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

    switch input_mode {
    case .COMMAND:
        return
    case .BUFFER_INPUT:
        if is_key_down(glfw.KEY_LEFT_CONTROL) {
            return
        }

        insert_into_buffer(key)
    case .BROWSER_SEARCH:
        browser_append_to_search_term(key)
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
scroll_callback :: proc "c" (handle: glfw.WindowHandle, scroll_x,scroll_y: f64) {
    scroll_amount := abs(scroll_y * .1)
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

    if active_buffer != nil {
        handle_buffer_input() or_return
    }

    return false
}

