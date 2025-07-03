#+private file
package main

import "core:os"
import fp "core:path/filepath"
import "core:strings"
import "core:fmt"
import "core:math"
import "core:unicode/utf8"
import "vendor:glfw"

show_browser_view := false

browser_view_y : f32
browser_view_width : f32 = 0

suppress := true

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
        fmt.println("CD'd", cwd)
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
            
            if os.exists(file) == false {
                return
            }

            if os.is_dir(file) {
                err := os.remove_directory(file)

                if err != os.General_Error.None {
                    return
                }
            } else {
                err := os.remove(file)

                if err != os.General_Error.None {
                    create_alert(
                        "Failed to delete file.",
                        "This is most likely due to missing permissions.",
                        5,
                        context.allocator,
                    )
                    
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

        if end_idx == -1 {
            return
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
    
    if is_key_pressed(glfw.KEY_U) && is_key_down(glfw.KEY_LEFT_CONTROL) {
        if strings.ends_with(search_term, "/") {
            search_term = search_term[:len(search_term) - 1]
        }
        
        dir := fp.dir(search_term, context.temp_allocator)
        
        if dir == "." {
            return
        } else {
            search_term = strings.concatenate({
                dir,
                dir != "/" ? "/" : "",
            })
        }
        
        return
    }

    if is_key_pressed(glfw.KEY_J) && is_key_down(glfw.KEY_LEFT_CONTROL) {
        item_offset = clamp(item_offset + 1, 0, len(found_files)-1)

        // set_found_files()

        return
    }

    if is_key_pressed(glfw.KEY_K) && is_key_down(glfw.KEY_LEFT_CONTROL) {
        item_offset = clamp(item_offset - 1, 0, len(found_files)-1)

        // set_found_files()

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
            search_term = strings.concatenate({
                found_files[target], "/",
            })
        
            set_found_files()
    
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

        de := os.get_env("XDG_CURRENT_DESKTOP") 

        if de == "GNOME" {
            glfw.WaitEvents()
        }

        delete(de)


        input_mode = .BROWSER_SEARCH

        search_term = strings.concatenate({
            cwd, "/",
        })

        set_found_files()

        return
    }
}

set_found_files :: proc() {
    clear(&cached_dirs)
    clear(&found_files)

    dirs_searched := 0
    file_index := 0
    
    search_dir : string

    glob := fp.base(search_term)

    if strings.ends_with(search_term, "/") /*os.is_dir(search_term)*/ {
        glob = "."

        search_dir = strings.clone(search_term)
    } else {
        search_dir = fp.dir(search_term)
    }

    defer delete(search_dir)
    
    queue: [dynamic]string
    append_elem(&queue, search_dir)

    for len(queue) > 0 && dirs_searched < 20 && file_index < 100 {
        dir := queue[0]
        ordered_remove(&queue, 0)
        dirs_searched += 1

        fd, err := os.open(dir)
        defer os.close(fd)

        hits: []os.File_Info
        if cached, ok := cached_dirs[dir]; ok {
            hits = cached
        } else {
            hits, err = os.read_dir(fd, -1)
            cached_dirs[dir] = hits
        }
        
        for hit in hits {
            if strings.contains(hit.name, glob) || glob == "" {
                if hit.fullpath == search_term /*hit.name == glob*/ {
                    inject_at(&found_files, 0, hit.fullpath)
                } else {
                    append_elem(&found_files, hit.fullpath)
                }
            }

            if hit.is_dir {
                skip := false
                for ign in search_ignored_dirs {
                    if hit.name == ign {
                        skip = true
                        break
                    }
                }
                if !skip {
                    append_elem(&queue, hit.fullpath)
                }
            }
        }
        
        // if after reading a directory,
        // check if we exceeded the maximum limit of files.
        // this lets big folders get ever hit in.
        file_index += 1
        if file_index >= 50 {
            break
        }
    }
}

initial_dir :: proc() -> string {
    if os.is_dir(search_term) {
        return strings.clone(search_term)
    }
    return fp.dir(search_term)
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
    
    // NOTE: disabled because annoying. pls no renable
    /*
    if os.is_dir(search_term) {
        last_char := search_term[len(search_term)-1:]

        if last_char != "/" && last_char != "." {
            search_term = strings.concatenate({
                search_term, "/",
            })
        }
    }
    */
    
    set_found_files()

    delete(runes)

    item_offset = 0
}

@(private="package")
draw_browser_view :: proc() {
    if suppress {
        return
    }
    
    small_text := math.round_f32(font_base_px * small_text_scale)
    normal_text := math.round_f32(font_base_px * normal_text_scale)
    large_text := math.round_f32(font_base_px * large_text_scale)
    
    padding := normal_text * .5

    one_width_percentage := fb_size.x / 100
    one_height_percentage := fb_size.y / 100

    margin := one_width_percentage * 20
    
    start_z : f32 = 20

    if fb_size.x < 900 {
        margin = 20
    }
    
    reset_rect_cache(&rect_cache)
    defer draw_rects(&rect_cache)
        
    bg_rect := rect{
        margin,
        browser_view_y,
        fb_size.x - (margin * 2),
        80 * one_height_percentage,
    }
    
    // Draw Background
    {
        add_rect(
            &rect_cache,
            bg_rect,
            no_texture,
            BG_MAIN_10,
            vec2{},
            start_z,
        )
        
        line_thickness := math.round_f32(font_base_px * line_thickness_em)
        
        border_rect := rect{
            bg_rect.x - line_thickness,
            bg_rect.y - line_thickness,
            bg_rect.width + line_thickness * 2,
            bg_rect.height + line_thickness * 2,
        }
        
        add_rect(
            &rect_cache,
            border_rect,
            no_texture,
            BG_MAIN_30,
            vec2{},
            start_z - .1,
        )
    }
    
    y_pen := bg_rect.y
    
    // Draw Search
    {
        search_size := measure_text(small_text, search_term)
        
        dir := fp.dir(search_term, context.temp_allocator)
        is_cwd := dir == cwd 
        
        cwd_size := is_cwd ? measure_text(small_text, "CWD") : vec2{}
        gap : f32 = is_cwd ? 5 : 0
        
        padding := small_text
        
        search_bar_height := search_size.y + cwd_size.y + gap + (padding * 2)
        
        search_rect := rect{
            bg_rect.x,
            bg_rect.y,
            bg_rect.width,
            search_bar_height,
        }
        
        add_rect(
            &rect_cache,
            search_rect,
            no_texture,
            BG_MAIN_20,
            vec2{},
            start_z + 1,
        )
        
        // Text
        {
            add_text(
                &rect_cache,
                vec2{
                    search_rect.x + padding,
                    search_rect.y + padding,
                },
                TEXT_MAIN,
                small_text,
                search_term,
                start_z + 2,
                false,
                search_rect.width - padding * 2,
            )
                
            if is_cwd {
                add_text(
                    &rect_cache,
                    vec2{
                        search_rect.x + padding,
                        search_rect.y + search_size.y + gap + padding,
                    },
                    TEXT_DARKEST,
                    small_text,
                    "CWD",
                    start_z + 2,
                )
            }
        }

        y_pen += search_bar_height
    }
    
    // Draw Controls
    {
        padding := small_text
        
        size := add_text_measure(
            &rect_cache,
            vec2{
                bg_rect.x + padding,
                y_pen + padding,
            },
            TEXT_DARKER,
            small_text,
            "Ctrl + [ D: Delete, JK: Scroll, F: Rename, G: Create, U: Up ]",
            start_z + 2,        
            false,
            bg_rect.width - padding * 2,
        )
        
        y_pen += (padding * 3)
    }
    
    // Draw Hits
    
    {
        padding := small_text
        
        max_width := bg_rect.width - padding * 2
                
        if len(search_term) == 0 {
            add_text(&rect_cache,
                vec2{
                    bg_rect.x + padding,
                    y_pen,
                },
                TEXT_DARKER,
                normal_text,
                "Enter a drive or directory.",
                start_z + 1,
            )
    
            return
        }
    
        if attempting_file_deletion {
            add_text(&rect_cache,
                vec2{
                    bg_rect.x + padding,
                    y_pen,
                },
                TEXT_MAIN,
                normal_text,
                "Are you sure you want to delete this file?\nCtrl+Enter to confirm, ESC to cancel.",
                start_z + 1,
                false,
                max_width,
                false,
                true,
            )
    
            return
        }
    
        if attempting_rename {
            add_text(&rect_cache,
                vec2{
                    bg_rect.x + padding,
                    y_pen,
                },
                TEXT_MAIN,
                normal_text,
                "Enter the new path for this file.\nPress Enter to confirm, ESC to cancel.",
                start_z + 1,
                false,
                -1,
                false,
                true,
            )
    
            return
        }
    
        start_idx := item_offset
        
        dir := fp.dir(search_term, context.temp_allocator)
    
        for found_file,index in found_files {
            if index < start_idx {
                continue
            }
    
            font_size : f32 = (index == start_idx) ? large_text : small_text
    
            gap := font_size * .5
    
            add_text(&rect_cache,
                vec2{
                    bg_rect.x + padding,
                    y_pen,
                },
                TEXT_MAIN,
                font_size,
                strings.concatenate({
                    index == start_idx ? "> " : "",
                    found_file[len(dir):]
                }, context.temp_allocator),
                start_z + 1,
                true,
                bg_rect.width - padding * 2,
                false,
            )
    
            y_pen += font_size + gap
    
            y_bound := (bg_rect.y+bg_rect.height)
    
            if y_pen + font_size + gap > y_bound {
                break
            } 
        }
    }
    
    /*
    bg_rect = rect{
        margin,
        browser_view_y,
        fb_size.x - (margin * 2),
        80 * one_height_percentage,
    }

    start_z : f32 = 20

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
    
    dir := fp.dir(search_term, context.temp_allocator)
    is_cwd := dir == cwd 

    add_rect(&rect_cache,
        rect{
            bg_rect.x,
            bg_rect.y,
            bg_rect.width,
            (normal_text) + padding * (is_cwd ? 3 : 2),
        },
        no_texture,
        BG_MAIN_30,
        vec2{},
        start_z + 1,
    )
    
    add_text(&rect_cache,
        pen,
        TEXT_MAIN,
        small_text,
        search_term,
        start_z + 2,
        true,
        bg_rect.width - padding * 2,
    )

    pen.y += (normal_text + 5)

    if is_cwd {
        add_text(&rect_cache,
            pen,
            TEXT_DARKER,
            small_text,
            "CWD",
            start_z + 2,
            true,
            bg_rect.width - padding * 3,
        )

        pen.y += small_text + (padding * 2)
    } else {
        pen.y += small_text + (padding)
    }
    */
}

@(private="package")
tick_browser_view :: proc() {
    normal_text := math.round_f32(font_base_px * normal_text_scale)
    padding := normal_text * 1.5

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

