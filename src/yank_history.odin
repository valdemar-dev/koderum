#+private file
package main

suppress := true

@(private="package")
show_yank_history :: proc() {
}

@(private="package")
draw_yank_history :: proc() {
    if suppress do return
    
    reset_rect_cache(&rect_cache)
}