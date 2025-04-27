#+private file
package main

import "core:os"
import fp "core:path/filepath"
import "core:strings"
import "core:fmt"
import "core:unicode/utf8"
import "vendor:glfw"

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

@(private="package")
cached_dirs : map[string][]os.File_Info

search_term := ""

@(private="package")
handle_browser_input :: proc() {
    if is_key_pressed(glfw.KEY_BACKSPACE) {
        runes := utf8.string_to_runes(search_term)

        end_idx := len(runes)-1

        if end_idx == -1 {
            return
        }

        runes = runes[:end_idx]

        search_term = utf8.runes_to_string(runes)

        delete(runes)

        set_found_files()
    }

    if is_key_pressed(glfw.KEY_ENTER) {
        concat := strings.concatenate({
            cwd, "/", search_term,
        })

        defer delete(concat)

        if os.is_dir(concat) {
            os.set_current_directory(concat)
            cwd = os.get_current_directory()
            search_term = ""

            return
        }

        if len(found_files) < 1 {
            return
        }

        open_file(found_files[0])

        toggle_browser_view()

        search_term = ""
        
        return
    }

    if is_key_pressed(glfw.KEY_ESCAPE) {
        toggle_browser_view()

        search_term = ""
        
        return
    }
}

@(private="package")
toggle_browser_view :: proc() {
    if show_browser_view {
        show_browser_view = false

        input_mode = .COMMAND

        return
    } else {
        suppress = false
        show_browser_view = true

        input_mode = .BROWSER_SEARCH
        do_suppress_next_char_event = true

        set_found_files()

        return
    }
}

set_found_files :: proc() {
    clear(&found_files)

    dirs_searched := 0

    get_dir_files :: proc(
        dir: string,
        glob: string, 
        dirs_searched: ^int, 
    ) {
        fd, err := os.open(dir)
        defer os.close(fd)

        hits : []os.File_Info

        if dir in cached_dirs {
            hits = cached_dirs[dir]
        } else {
            if dirs_searched^ >= 20 {
                return
            }

            dirs_searched^ += 1

            hits, err = os.read_dir(fd,-1)

            cached_dirs[dir] = hits
        }

        for hit in hits {
            if glob == "." ||
            strings.contains(hit.fullpath, glob) {
                append_elem(&found_files, hit.fullpath)
            }

            if hit.is_dir == false {
                continue
            }

            if len(found_files) >= 50 {
                break
            }

            // TODO: add more of these
            if hit.name == ".git" {
                continue
            }

            get_dir_files(hit.fullpath, glob, dirs_searched) 
        } 
    }

    concat := strings.concatenate({
        cwd, "/", search_term,
    })

    dir := fp.dir(concat)

    base := fp.base(concat)

    if os.is_dir(concat) {
        base = "."
    }

    defer delete(concat)
    defer delete(dir)

    get_dir_files(dir, base, &dirs_searched)
}

@(private="package")
browser_append_to_search_term :: proc(key: rune) {
    buf := make([dynamic]rune)

    runes := utf8.string_to_runes(search_term)
    
    append_elems(&buf, ..runes)
    append_elem(&buf, key)

    search_term = utf8.runes_to_string(buf[:])

    set_found_files()

    delete(runes)
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
        vec2{},
        start_z,
    )

    search_term := strings.concatenate({
        cwd,"/",search_term,
    })

    st_size := measure_text(ui_general_font_size, search_term)

    add_text(&rect_cache,
        vec2{
            bg_rect.x + bg_rect.width - st_size.x - padding,
            bg_rect.y + padding,
        },
        TEXT_MAIN,
        ui_general_font_size,
        search_term,
        start_z + 1,
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

