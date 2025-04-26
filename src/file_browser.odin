#+private file
package main

import "core:os"
import fp "core:path/filepath"
import "core:strings"
import "core:fmt"

show_browser_view := false

browser_view_y : f32
browser_view_width : f32 = 0

suppress := true

padding :: 20

bg_rect : rect

@(private="package")
cwd : string

@(private="package")
found_files : [dynamic]string

search_term := "/*"

@(private="package")
toggle_browser_view :: proc() {
    if show_browser_view {
        show_browser_view = false

        return
    } else {
        suppress = false
        show_browser_view = true

        set_found_files()

        return
    }
}

set_found_files :: proc() {
    concat := strings.concatenate({
        cwd,
        search_term,
    })

    hits, err := fp.glob(concat)

    assert(err == .None)

    clear(&found_files)
    append_elems(&found_files, ..hits)

    fmt.println(found_files)
}

filter_files :: proc(search_term: string) {
    new_found_files := make([dynamic]string, len(found_files))

    for found_file in found_files {
        if found_file != search_term {
            continue
        }

        append(&new_found_files, found_file)
    }

    clear(&found_files)
    found_files = new_found_files
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

    size := add_text_measure(&rect_cache,
        pen,
        TEXT_MAIN, 
        ui_general_font_size,
        "Browser",
        start_z + 1,
    )

    pen.y += ui_general_font_size

    for found_file in found_files {
        add_text(&rect_cache,
            pen,
            TEXT_MAIN,
            ui_smaller_font_size,
            found_file,
            start_z + 1,
        )

        pen.y += ui_smaller_font_size

        y_bound := (bg_rect.y+bg_rect.height)

        if pen.y + ui_smaller_font_size + padding > y_bound {
            break
        } 
    }

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

