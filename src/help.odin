#+private file
package main

import "vendor:glfw"

x := 0
width := 0

suppress := true
is_open := false

@(private="package")
handle_help_input :: proc() {
    if is_key_pressed(glfw.KEY_F1) {
        toggle_help_menu()
        
        return
    }
}

@(private="package")
tick_help :: proc() {
    if suppress {
        x = 0 - width
    }
}

@(private="package")
toggle_help_menu :: proc() {
    if is_open == true {
        is_open = false
        
        input_mode = .COMMAND
        
        return
    }
    
    is_open = true
    suppress = false
    
    set_mode(mode = .HELP, key = glfw.KEY_PERIOD, char = '.')
}

@(private="package")
draw_help :: proc() {
    if suppress do return
}