#+private file
package main

import "core:fmt"
import "core:strings"
import "core:os"
import "core:time"

show_buffer_info_view := false

buffer_info_view_x : f32
buffer_info_view_width : f32 = 0

suppress := true

padding :: 20

sb := strings.builder_make()
sb_string : string

@(private="package")
toggle_buffer_info_view :: proc() {
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

    reset_rect_cache(&rect_cache)

    pos_rect := rect{
        buffer_info_view_x,
        50,
        0,
        0,
    }

    start_z : f32 = 30

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

    size = add_text_measure(&rect_cache,
        pen,
        TEXT_MAIN,
        ui_smaller_font_size,
        strings.concatenate({"CWD: ", cwd}, context.temp_allocator),
        start_z + 2
    )

    if size.x > buffer_info_view_width {
        buffer_info_view_width = size.x
    }

    pen.y += ui_smaller_font_size + padding



    strings.write_string(&sb, "Bytes: ")
    strings.write_i64(&sb, active_buffer.info.size)

    size_string := strings.to_string(sb)
    strings.builder_reset(&sb)

    size = add_text_measure(&rect_cache,
        pen,
        TEXT_MAIN,
        ui_smaller_font_size,
        size_string,
        start_z + 2
    )

    if size.x > buffer_info_view_width {
        buffer_info_view_width = size.x
    }

    pen.y += ui_smaller_font_size + padding

    strings.write_string(&sb, "Created: ")

    creation_date,_ := time.time_to_datetime(active_buffer.info.creation_time) 

    strings.write_i64(&sb, creation_date.year)
    strings.write_string(&sb, "-")
    strings.write_i64(&sb, i64(creation_date.month))
    strings.write_string(&sb, "-")
    strings.write_i64(&sb, i64(creation_date.day))
    strings.write_string(&sb, " @ ")
    strings.write_i64(&sb, i64(creation_date.hour))
    strings.write_string(&sb, ":")
    strings.write_i64(&sb, i64(creation_date.minute))
    strings.write_string(&sb, ":")
    strings.write_i64(&sb, i64(creation_date.second))

    created_string := strings.to_string(sb)

    strings.builder_reset(&sb)

    size = add_text_measure(&rect_cache,
        pen,
        TEXT_MAIN,
        ui_smaller_font_size,
        created_string,
        start_z + 2
    )

    if size.x > buffer_info_view_width {
        buffer_info_view_width = size.x
    }

    pen.y += ui_smaller_font_size + padding

    strings.write_string(&sb, "Modified: ")

    edited_date ,_ := time.time_to_datetime(active_buffer.info.modification_time)

    strings.write_i64(&sb, edited_date.year)
    strings.write_string(&sb, "-")
    strings.write_i64(&sb, i64(edited_date.month))
    strings.write_string(&sb, "-")
    strings.write_i64(&sb, i64(edited_date.day))
    strings.write_string(&sb, " @ ")
    strings.write_i64(&sb, i64(edited_date.hour))
    strings.write_string(&sb, ":")
    strings.write_i64(&sb, i64(edited_date.minute))
    strings.write_string(&sb, ":")
    strings.write_i64(&sb, i64(edited_date.second))

    edited_string := strings.to_string(sb)

    strings.builder_reset(&sb)

    size = add_text_measure(&rect_cache,
        pen,
        TEXT_MAIN,
        ui_smaller_font_size,
        edited_string,
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

    draw_rects(&rect_cache)
}

@(private="package")
tick_buffer_info_view :: proc() {
    if suppress == true {
        buffer_info_view_x = fb_size.x

        return
    }

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
