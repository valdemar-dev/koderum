#+private file
package main

show_browser_view := false

browser_view_y : f32
browser_view_width : f32 = 0

suppress := true

padding :: 20

bg_rect : rect

@(private="package")
toggle_browser_view :: proc() {
    if show_browser_view {
        show_browser_view = false

        return
    } else {
        suppress = false
        show_browser_view = true

        return
    }
}

@(private="package")
draw_browser_view :: proc() {
    if suppress {
        return
    }

    one_width_percentage := fb_size.x / 100
    one_height_percentage := fb_size.y / 100

    bg_rect = rect{
        one_width_percentage * 20,
        browser_view_y,
        fb_size.x - (one_width_percentage * 40),
        80 * one_height_percentage,
    }

    start_z : f32 = 3

    pen := vec2{
        bg_rect.x + padding,
        bg_rect.y + padding,
    }

    reset_rect_cache(&rect_cache)

    add_rect(&rect_cache,
        bg_rect,
        no_texture,
        BG_MAIN_20,
    )

    add_text(&rect_cache,
        pen,
        TEXT_MAIN, 
        ui_general_font_size,
        "Browser",
        start_z + 1,
    )

    draw_rects(&rect_cache)
}

@(private="package")
tick_browser_view :: proc() {
    if show_browser_view {
        start_y := status_bar_rect.y + status_bar_rect.height

        browser_view_y = smooth_lerp(
            browser_view_y,
            start_y + (padding * 2),
            100,
            frame_time,
        )
    } else {
        browser_view_y = smooth_lerp(
            browser_view_y,
            fb_size.y,
            100,
            frame_time,
        )

        if int(fb_size.x) - int(browser_view_y) < 5 {
        }
    }
}

