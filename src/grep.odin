package main

import "core:os"
import "core:os/os2"

import fp "core:path/filepath"
import "core:strings"
import "core:fmt"
import "core:math"
import "core:strconv"
import "core:unicode/utf8"
import "vendor:glfw"
import "core:thread"

show_browser_view := false

browser_view_y : f32
browser_view_width : f32 = 0

suppress := true

bg_rect : rect

GrepResult :: struct {
    file_name: string,
    content: string,
    line: int,
}

grep_found_files : [dynamic]GrepResult

search_term := ""


grep_progress_text : string

item_offset := 0

@(private="package")
handle_grep_input :: proc() {
    if is_key_pressed(mapped_keybinds[.REMOVE_CHARACTER]) {
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
   
    is_pressing_control := is_key_down(glfw.KEY_LEFT_CONTROL) || is_key_down(glfw.KEY_RIGHT_CONTROL)
    
    if is_key_pressed(mapped_keybinds[.MOVE_DOWN]) && is_pressing_control {
        item_offset = clamp(item_offset + 1, 0, len(grep_found_files)-1)

        return
    }

    if is_key_pressed(mapped_keybinds[.MOVE_UP]) && is_pressing_control {
        item_offset = clamp(item_offset - 1, 0, len(grep_found_files)-1)

        return
    }

    if is_key_pressed(mapped_keybinds[.ENTER]) {
        if len(grep_found_files) < 1 {
            return
        }

        target := item_offset
        hit := grep_found_files[target]
        
        open_file(
            strings.concatenate({ cwd, "/", hit.file_name, })
        )
        
        toggle_grep_view()
        
        go_to_line(hit.line-1, 0)
        
        return
    }

    if is_key_pressed(mapped_keybinds[.ESCAPE]) {
        toggle_grep_view()
 
        return
    }
}

@(private="package")
toggle_grep_view :: proc() {
    if show_browser_view {
        show_browser_view = false

        input_mode = .COMMAND

        return
    } else {
        set_mode(.GREP_SEARCH, mapped_keybinds[.ENTER_FILE_BROWSER_MODE])

        suppress = false
        show_browser_view = true
        
        search_term = ""

        set_found_files()
        
        return
    }
}

run_command_output :: proc(cmd: []string, env: []string) -> (output: string, ok: bool) {
    context = global_context
    
    desc := os2.Process_Desc{
        cwd,
        cmd,
        env,
        nil,
        nil,
        nil,
    }

    _, stdout, stderr, err := os2.process_exec(desc, context.allocator)
    
    defer delete(stderr)
    defer delete(stdout)
    
    if err != os2.ERROR_NONE {
        return strings.clone(string(stdout)), false
    }
    
    return strings.clone(string(stdout)), true
}


set_found_files_thread : ^thread.Thread

set_found_files :: proc() {
    if set_found_files_thread != nil {
        thread.terminate(set_found_files_thread, 9)
        thread.destroy(set_found_files_thread)
    }
    
    set_found_files_thread = thread.create(set_found_files_threaded)
    thread.start(set_found_files_thread)
}

set_found_files_threaded :: proc(thread: ^thread.Thread) {
    context = global_context
    
    for file in grep_found_files {
        delete(file.file_name)
        delete(file.content)
    }

    clear(&grep_found_files)
    
    if search_term == "" {
        return
    }
    
    grep_progress_text = "Searching.."

    escaped_term, _ := strings.replace_all(strings.clone(search_term), "\"", "\\\"")
    
    concat := strings.concatenate({
        `grep -Rn -A10 "`,escaped_term,`" . | head -n 600`,
    })
    defer delete(concat)
    
    cmd := []string{
        "/bin/sh", "-c", concat
    }
    
    defer delete(escaped_term)

    output, ok := run_command_output(cmd, {})
    defer delete(output)

    if !ok {
        create_alert(
            "Failed to run grep.",
            "There was an error executing the grep command.",
            5,
            context.allocator,
        )
        return
    }

    lines := strings.split_lines(output)
    defer delete(lines)
    
    content_builder: strings.Builder
    strings.builder_init(&content_builder)
    defer strings.builder_destroy(&content_builder)

    current_file := ""
    current_line := 0

    for line in lines {
        if line == "" do continue
        
        if line == "--" {
            if current_file != "" && current_line != 0 {
                append(&grep_found_files, GrepResult{
                    file_name = strings.clone(current_file),
                    line = current_line,
                    content = strings.clone(strings.to_string(content_builder)),
                })
            }
            current_file = ""
            current_line = 0
            strings.builder_reset(&content_builder)
            continue
        }
        
        idx := strings.index_any(line, ":-")
        
        if idx > 0 {
            filename := line[:idx]
            sep := line[idx]
            rest := line[idx+1:]
            second_idx := strings.index_byte(rest, sep)
            
            if second_idx > 0 {
                line_num_str := rest[:second_idx]
                content_str := rest[second_idx+1:]
                line_num, ok := strconv.parse_int(line_num_str)
                
                if ok {
                    if current_file == "" {
                        current_file = filename
                    }
                    if strings.builder_len(content_builder) > 0 {
                        strings.write_string(&content_builder, "\n")
                    }
                    strings.write_string(&content_builder, content_str)
                    if sep == ':' {
                        current_line = line_num
                    }
                }
            }
        }
    }

    // Process the last block if any
    if current_file != "" && current_line != 0 {
        append(&grep_found_files, GrepResult{
            file_name = strings.clone(current_file),
            line = current_line,
            content = strings.clone(strings.to_string(content_builder)),
        })
    }
    
    if len(grep_found_files) == 0 {
        grep_progress_text = "No Hits Found!"
    }
}

@(private="package")
grep_append_to_search_term :: proc(key: rune) {
    buf := make([dynamic]rune)

    runes := utf8.string_to_runes(search_term)
    
    append_elems(&buf, ..runes)
    append_elem(&buf, key)

    search_term = utf8.runes_to_string(buf[:])
    
    set_found_files()

    delete(runes)

    item_offset = 0
}

@(private="package")
draw_grep_view :: proc() {
    if suppress {
        return
    }
    
    small_text := math.round_f32(font_base_px * small_text_scale)
    normal_text := math.round_f32(font_base_px * normal_text_scale)
    large_text := math.round_f32(font_base_px * large_text_scale)
    
    padding := normal_text * .5

    one_width_percentage := fb_size.x / 100
    one_height_percentage := fb_size.y / 100

    margin := font_base_px * 4
    
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
        
        padding := small_text
        
        search_bar_height := search_size.y + (padding * 2)
        
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
            "Ctrl + [ JK: Scroll ]",
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
                "Enter a search term.",
                start_z + 1,
            )
            
            return
        } else if len(grep_found_files) == 0 {
            add_text(&rect_cache,
                vec2{
                    bg_rect.x + padding,
                    y_pen,
                },
                TEXT_DARKER,
                normal_text,
                grep_progress_text,
                start_z + 1,
            )
            
            return            
        }
        
        start_idx := item_offset
        
        if len(grep_found_files) > 0 {
            offset_x := bg_rect.width / 2
            font_size : f32 = small_text
            
            gap := font_size * .5
    
            add_text(&rect_cache,
                vec2{
                    bg_rect.x + padding + offset_x,
                    y_pen,
                },
                TEXT_MAIN,
                font_size,
                grep_found_files[item_offset].content,
                start_z + 3,
                true,
                (bg_rect.width - offset_x) - padding * 2,
                false,
                true,
                bg_rect.y + bg_rect.height - y_pen - padding,
            )
        }
        
        for found_file,index in grep_found_files {
            if index < start_idx {
                continue
            }
            
            font_size : f32 = small_text
            
            gap := font_size * .5
            
            display_file := strings.trim_prefix(found_file.file_name, "./")
            
            add_text(&rect_cache,
                vec2{
                    bg_rect.x + padding,
                    y_pen,
                },
                TEXT_MAIN,
                font_size,
                strings.concatenate({
                    index == start_idx ? "> " : "",
                    display_file
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
}

@(private="package")
tick_grep_view :: proc() {
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
