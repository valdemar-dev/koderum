#+private file
package main

x := 0
width := 0

suppress := true

@(private="package")
handle_help_input :: proc() {
}

@(private="package")
tick_help :: proc() {
    if suppress {
        x = 0 - width
    }
}

@(private="package")
draw_help :: proc() {
    if suppress do return
    
    
}