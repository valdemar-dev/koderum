#+private file
package main

import "vendor:glfw"
import "core:fmt"
import "base:runtime"
import "core:math"

ActiveKey :: struct {
    is_down: bool,
    is_pressed: bool,
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

click_pos := Click{}

key_store : map[i32]ActiveKey = {}

@(private="package")
is_key_down :: proc(key: i32) -> bool {
    return key_store[key].is_down
}

@(private="package")
is_key_pressed :: proc(key: i32) -> bool {
    return key_store[key].is_pressed
}

@(private="package")
process_input :: proc() {
    context = runtime.default_context()

    if is_key_down(glfw.KEY_ESCAPE) {
        glfw.SetWindowShouldClose(window, true)
    }

    set_keypress_states()
}

@(private="package")
key_callback :: proc "c" (handle: glfw.WindowHandle, key, scancode, action, mods: i32) {
    switch action {
    case glfw.RELEASE:
        key_store[key] = ActiveKey{
            is_down=false,
            is_pressed=false,
        }

        break
    case glfw.PRESS: 
        key_store[key] = ActiveKey{
            is_pressed=true,
            is_down=true,
        }

        break
    }
}

set_keypress_states :: proc() {
    for key, &active_key in key_store {
        active_key = ActiveKey{
            is_down=active_key.is_down,
            is_pressed=false,
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
