#+private file
package main

import "core:fmt"

show_buffer_info_view := false

buffer_info_view_x : f32
buffer_info_view_width : f32 = 0

suppress := true

padding :: 20

@(private="package")
toggle_buffer_info_view :: proc() {

        fmt.println(show_buffer_info_view)

    if show_buffer_info_view {
        show_buffer_info_view = false

        return
    } else {
        suppress = false
        show_buffer_info_view = true

        return
    }
}

@(private="package")
draw_buffer_info_view :: proc() {
    if suppress {
        return
    }

    pos_rect := rect{
        buffer_info_view_x,
        50,
        0,
        0,
    }

    start_z : f32 = 3

    pen := vec2{
        pos_rect.x + padding,
        pos_rect.y + padding,
    }

    size := add_text_measure(&rect_cache,
        pen,
        TEXT_MAIN,
        ui_general_font_size,
        "File Info",
        start_z + 2,
    )

    if size.x > buffer_info_view_width {
        buffer_info_view_width = size.x
    }

    pen.y += ui_general_font_size + padding

    size = add_text_measure(&rect_cache,
        pen,
        TEXT_MAIN,
        ui_smaller_font_size,
        active_buffer.info.fullpath,
        start_z + 2
    )

    if size.x > buffer_info_view_width {
        buffer_info_view_width = size.x
    }

    pen.y += ui_smaller_font_size + padding

    add_rect(&rect_cache,
        rect{
            pos_rect.x,
            pos_rect.y,
            buffer_info_view_width + padding * 2,
            pen.y - pos_rect.y,
        },
        no_texture,
        BG_MAIN_20,
        vec2{},
        start_z + 1,
    )
}

@(private="package")
tick_buffer_info_view :: proc() {
    if show_buffer_info_view {
        buffer_info_view_x = smooth_lerp(
            buffer_info_view_x,
            fb_size.x - (padding * 3) - buffer_info_view_width,
            100,
            frame_time,
        )
    } else {
        buffer_info_view_x = smooth_lerp(
            buffer_info_view_x,
            fb_size.x,
            100,
            frame_time,
        )

        if int(fb_size.x) - int(buffer_info_view_x) < 5 {
            suppress = true
        }
    }
}
