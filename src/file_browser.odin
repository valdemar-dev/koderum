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

        when ODIN_OS == .Windows {
            if end_idx == -1 {
                return
            }
        } else {
            if end_idx == 0 {
                return
            }
        }
        

        runes = runes[:end_idx]

        search_term = utf8.runes_to_string(runes)

        delete(runes)

        set_found_files()
    }

    if is_key_pressed(glfw.KEY_ENTER) {
        change_dir :: proc(dir: string) {
            os.set_current_directory(dir)
            cwd = os.get_current_directory()

            search_term = strings.concatenate({
                cwd, "/",
            })

            when ODIN_DEBUG {
                fmt.println("CD'd to", cwd)
            }

            set_found_files()

            return
        }

        if os.is_dir(search_term) {
            change_dir(search_term)

            return
        }

        if len(found_files) < 1 {
            return
        }

        if os.is_dir(found_files[0]) {
            change_dir(found_files[0])

            return
        }


        open_file(found_files[0])

        toggle_browser_view()
        
        return
    }

    if is_key_pressed(glfw.KEY_ESCAPE) {
        toggle_browser_view()
 
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

        search_term = strings.concatenate({
            cwd, "/",
        })

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
            if strings.contains(hit.name, glob) {
                if hit.name == glob {
                    inject_at(&found_files, 0, hit.fullpath)

                } else {
                    append_elem(&found_files, hit.fullpath)
                }
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

    dir : string

    base := fp.base(search_term)

    if os.is_dir(search_term) {
        base = "."

        dir = strings.clone(search_term)
    } else {
        dir = fp.dir(search_term)
    }

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

    if os.is_dir(search_term) {
        last_char := search_term[len(search_term)-1:]

        if last_char != "/" && last_char != "." {
            search_term = strings.concatenate({
                search_term, "/",
            })
        }
    }
    
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

    margin := one_width_percentage * 20

    if fb_size.x < 900 {
        margin = 20
    }

    bg_rect = rect{
        margin,
        browser_view_y,
        fb_size.x - (margin * 2),
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

    add_rect(&rect_cache,
        rect{
            bg_rect.x,
            bg_rect.y,
            bg_rect.width,
            ui_general_font_size + padding * 2,
        },
        no_texture,
        BG_MAIN_30,
        vec2{},
        start_z + 1,
    )

    add_text(&rect_cache,
        pen,
        TEXT_MAIN,
        ui_smaller_font_size,
        search_term,
        start_z + 2,
    )

    pen.y += (ui_general_font_size + padding * 2)

    if len(search_term) == 0 {
        add_text(&rect_cache,
            pen,
            TEXT_MAIN,
            font_size,
            "Enter the name of a directory to start searching.",
            start_z + 1,
        )

        draw_rects(&rect_cache)

        return
    }

    dir := fp.dir(search_term, context.temp_allocator)

    for found_file,index in found_files {
        font_size : f32 = (index == 0) ? ui_bigger_font_size : ui_smaller_font_size

        gap := font_size * .5

        add_text(&rect_cache,
            pen,
            TEXT_MAIN,
            font_size,
            found_file[len(dir):],
            start_z + 1,
            true,
            bg_rect.width - padding * 2,
            false,
        )

        pen.y += font_size + gap

        y_bound := (bg_rect.y+bg_rect.height)

        if pen.y + font_size + gap > y_bound {
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

