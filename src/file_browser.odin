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

item_offset := 0 

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

attempting_file_deletion : bool = false

attempting_rename : bool = false
renaming_file_name : string

@(private="package")
handle_browser_input :: proc() {
    if attempting_file_deletion {
        if (
            is_key_pressed(glfw.KEY_ENTER) &&
            is_key_down(glfw.KEY_LEFT_CONTROL)
        ) {
            target := item_offset

            file := found_files[target]

            if os.is_dir(file) {
                err := os.remove_directory(file)

                if err != os.General_Error.None {
                    return
                }
            } else {
                err := os.remove(file)

                if err != os.General_Error.None {
                    return
                }
            }

            dir := fp.dir(search_term, context.temp_allocator)
            delete_key(&cached_dirs, dir)

            attempting_file_deletion = false

            set_found_files()

            return
        }

        if is_key_pressed(glfw.KEY_ESCAPE) {
            attempting_file_deletion = false

            return
        }

        return
    }

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

        item_offset = 0

        set_found_files()
    }

    if attempting_rename {
        if is_key_pressed(glfw.KEY_ESCAPE) {
            attempting_rename = false

            concat := strings.concatenate({
                cwd, "/",
            })

            search_term = concat

            set_found_files()

            return
        }

        if is_key_pressed(glfw.KEY_ENTER) {
            os.rename(renaming_file_name, search_term)

            attempting_rename = false

            dir := fp.dir(search_term)

            delete_key(&cached_dirs, dir)

            search_term = strings.concatenate({dir, "/"})

            set_found_files()

            return
        }

        return
    }
   
    if is_key_pressed(glfw.KEY_F) && is_key_down(glfw.KEY_LEFT_CONTROL) {
        attempting_rename = true

        if len(found_files) < 1 {
            return
        }

        old := found_files[item_offset]

        renaming_file_name = old
        search_term = old

        return
    }

    if is_key_pressed(glfw.KEY_J) && is_key_down(glfw.KEY_LEFT_CONTROL) {
        item_offset = clamp(item_offset + 1, 0, len(found_files)-1)

        set_found_files()

        return
    }

    if is_key_pressed(glfw.KEY_K) && is_key_down(glfw.KEY_LEFT_CONTROL) {
        item_offset = clamp(item_offset - 1, 0, len(found_files)-1)

        set_found_files()

        return
    }

    if is_key_pressed(glfw.KEY_S) && is_key_down(glfw.KEY_LEFT_CONTROL) {
        dir := fp.dir(search_term, context.temp_allocator)

        os.set_current_directory(dir)
        cwd = os.get_current_directory()

        return
    }

    if is_key_pressed(glfw.KEY_D) && is_key_down(glfw.KEY_LEFT_CONTROL) {
        attempting_file_deletion = true
    }

    if is_key_pressed(glfw.KEY_G) && is_key_down(glfw.KEY_LEFT_CONTROL) {
        if os.exists(search_term) {
            return
        }

        success := os.write_entire_file(search_term, {})

        if !success {
            return
        }

        dir := fp.dir(search_term, context.temp_allocator)
        delete_key(&cached_dirs, dir)

        toggle_browser_view()
        open_file(search_term)

        return
    }

    if is_key_pressed(glfw.KEY_ENTER) {
        if len(found_files) < 1 {
            return
        }

        target := item_offset

        if os.is_dir(found_files[target]) {
            change_dir(found_files[target])

            return
        }

        open_file(found_files[target])
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

        glfw.WaitEvents()

        input_mode = .BROWSER_SEARCH

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
    file_index := 0

    get_dir_files :: proc(
        dir: string,
        glob: string, 
        dirs_searched: ^int, 
        file_index: ^int
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

            file_index^ += 1

            if hit.is_dir == false {
                continue
            }

            if file_index^ >= 50 {
                break
            }

            // TODO: add more of these
            if hit.name == ".git" {
                continue
            }

            get_dir_files(hit.fullpath, glob, dirs_searched, file_index) 
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

    get_dir_files(dir, base, &dirs_searched, &file_index)
}

@(private="package")
browser_append_to_search_term :: proc(key: rune) {
    if attempting_file_deletion {
        return
    }

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

    item_offset = 0
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
        true,
        bg_rect.width - padding * 2,
    )

    pen.y += (ui_general_font_size + 5)

    dir := fp.dir(search_term, context.temp_allocator)

    if dir == cwd {
        add_text(&rect_cache,
            pen,
            TEXT_DARKER,
            ui_smaller_font_size,
            "CWD",
            start_z + 2,
            true,
            bg_rect.width - padding * 2,
        )
    }

    pen.y += ui_smaller_font_size + (padding * 2)

    if len(search_term) == 0 {
        add_text(&rect_cache,
            pen,
            TEXT_DARKER,
            ui_general_font_size,
            "Enter a drive or directory.",
            start_z + 1,
        )

        draw_rects(&rect_cache)

        return
    }

    if attempting_file_deletion {
        add_text(&rect_cache,
            pen,
            TEXT_MAIN,
            ui_general_font_size,
            "Are you sure you want to delete this file?\nCtrl+Enter to confirm, ESC to cancel.",
            start_z + 1,
            false,
            -1,
            false,
            true,
        )

        draw_rects(&rect_cache)

        return
    }

    if attempting_rename {
        add_text(&rect_cache,
            pen,
            TEXT_MAIN,
            ui_general_font_size,
            "Enter the new path for this file.\nPress Enter to confirm, ESC to cancel.",
            start_z + 1,
            false,
            -1,
            false,
            true,
        )

        draw_rects(&rect_cache)

        return
    }

    start_idx := item_offset

    for found_file,index in found_files {
        if index < start_idx {
            continue
        }

        font_size : f32 = (index == start_idx) ? ui_bigger_font_size : ui_smaller_font_size

        gap := font_size * .5

        add_text(&rect_cache,
            pen,
            TEXT_MAIN,
            ui_general_font_size,
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

        if int(fb_size.y) - int(browser_view_y) < 5 {
        }
    }
}

