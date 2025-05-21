#+private file
#+feature dynamic-literals
package main
import "core:os"
import "core:fmt"
import "core:strings"
import gl "vendor:OpenGL"
import "vendor:glfw"
import "base:runtime"
import "core:unicode/utf8"
import "core:strconv"
import "core:path/filepath"
import ft "../../alt-odin-freetype"

@(private="package")
WordDef :: struct {
    start: i32,
    end: i32,
    color: vec4,
}

@(private="package")
BufferLine :: struct {
    characters: []rune,
    words: []WordDef,
}

Buffer :: struct {
    lines: ^[dynamic]BufferLine,
    x_offset: f32,

    x_pos: f32,
    y_pos: f32,

    width: f32,
    height: f32,

    file_name: string,
    ext: string,

    info: os.File_Info,

    is_saved: bool,

    cursor_line: int,
    cursor_char_index: int,

    scroll_position: f32,
    horizontal_scroll_position: f32,
}

@(private="package")
IndentType :: enum { 
    FORWARD,
    BACKWARD,
}

@(private="package")
IndentRule :: struct {
    type: IndentType,
}

@(private="package")
buffers : [dynamic]^Buffer

@(private="package")
active_buffer : ^Buffer

@(private="package")
buffer_scroll_position : f32

@(private="package")
buffer_horizontal_scroll_position : f32

sb := strings.builder_make()

SearchHit :: struct{
    line: int,
    start_char: int,
    end_char: int,
}

search_hits : [dynamic]SearchHit

@(private="package")
selected_hit : ^SearchHit = nil

@(private="package")
buffer_search_term : string

next_buffer :: proc() {
    set_next_as_current := false

    for buffer, index in buffers {
        if set_next_as_current == true {
            open_file(buffer.file_name)

            break
        } else if buffer.file_name == active_buffer.file_name {
            set_next_as_current = true

        }
    }
}

set_buffer :: proc(number: int) {
    idx := number - 1

    if idx > len(buffers) - 1 {
        return
    }

    buf := buffers[idx]
    open_file(buf.file_name)
}

prev_buffer :: proc() {
    set_next_as_current := false

    #reverse for buffer, index in buffers {
        if set_next_as_current == true {
            open_file(buffer.file_name)

            break
        } else if buffer.file_name == active_buffer.file_name {
            set_next_as_current = true
        }
    }
}

find_hits :: proc() {
    clear(&search_hits)

    runes := utf8.string_to_runes(buffer_search_term)

    for line,i in active_buffer.lines {
        found, idx := contains_runes(line.characters, runes)

        if found {
            append_elem(&search_hits, SearchHit{
                line=i,
                start_char=idx,
                end_char=idx + len(runes),
            })
        }
    }

    delete(runes)

    if len(search_hits) > 0 {
        set_hit_index(0)
    }
}

hit_index := 0
set_hit_index :: proc(index: int) {
    idx := index

    if idx > len(search_hits) - 1 {
        idx = 0
    } else if idx == -1 {
        idx = len(search_hits) - 1
    }

    selected_hit = &search_hits[idx]

    set_buffer_cursor_pos(
        selected_hit.line,
        selected_hit.start_char,
    )

    constrain_scroll_to_cursor()

    hit_index = idx
}

@(private="package")
draw_buffers :: proc() {
}

draw_buffer_line :: proc(
    buffer_line: ^BufferLine,
    index: int,
    input_pen: vec2,
    line_buffer: ^[dynamic]byte,
    line_pos: vec2,
    ascender: f32,
    descender: f32,
    char_map: ^CharacterMap,
    font_size: f32,
) -> vec2 {
    pen := input_pen

    true_font_height := ascender - descender

    line_height := true_font_height

    if line_pos.y < 0 {
        pen.y = pen.y + line_height

        return pen
    }

    chars := buffer_line.characters

    long_line := do_highlight_long_lines && (len(chars) >= long_line_required_characters)

    highlight_offset, highlight_width := add_code_text(
        line_pos,
        font_size,
        &chars,
        3,
        buffer_line,
        char_map,
        ascender,
        descender, 
        index,
    )

    if (
        input_mode == .HIGHLIGHT
    ) {
        add_rect(&rect_cache,
            rect{
                line_pos.x + highlight_offset,
                line_pos.y,
                highlight_width,
                true_font_height,
            },
            no_texture,
            text_highlight_bg,
            vec2{},
            2,
        )
    } else if do_highlight_current_line && buffer_cursor_line == index {
        add_rect(&rect_cache,
            rect{
                line_pos.x,
                line_pos.y,
                active_buffer.width,
                true_font_height,
            },
            no_texture,
            BG_MAIN_20,
            vec2{},
            2,
        )

        add_rect(&rect_cache,
            rect{
                line_pos.x,
                line_pos.y + true_font_height - general_line_thickness_px,
                active_buffer.width,
                general_line_thickness_px,
            },
            no_texture,
            BG_MAIN_30,
            vec2{},
            2.5,
        )

        add_rect(&rect_cache,
            rect{
                line_pos.x,
                line_pos.y,
                active_buffer.width,
                general_line_thickness_px,
            },
            no_texture,
            BG_MAIN_30,
            vec2{},
            2.5,
        )
    } 

    if do_draw_line_count {
        line_pos := vec2{
            pen.x + line_count_padding_px,
            pen.y - buffer_scroll_position
        }

        line_string := strconv.itoa(line_buffer^[:], index+1)

        add_text(&rect_cache,
            line_pos,
            long_line ? TEXT_ERROR : TEXT_DARKER,
            font_size,
            line_string,
            5,
        )
    }

    pen.y = pen.y + line_height

    return pen
}

draw_no_buffer :: proc() {
    reset_rect_cache(&rect_cache)
    reset_rect_cache(&text_rect_cache)

    add_rect(&rect_cache,
        rect{
            0,0,fb_size.x,fb_size.y,
        },
        no_texture,
        BG_MAIN_10,
        vec2{},
        -2,
    )

    size := measure_text(ui_bigger_font_size, "Press O to open a file.")

    add_text(&text_rect_cache,
        vec2{
            fb_size.x / 2 - size.x / 2,
            fb_size.y / 2 - size.y / 2,
        },
        TEXT_MAIN,
        ui_bigger_font_size,
        "Press O to open a file.",
    )

    draw_rects(&rect_cache)
    draw_rects(&text_rect_cache)
}

@(private="package")
draw_buffer :: proc() {
    if active_buffer == nil {
        draw_no_buffer()

        return
    }

    switch active_buffer.ext {
    case ".png":
        draw_image_buffer(active_buffer.ext)
    case:
        draw_text_buffer()
    }
}

draw_image_buffer :: proc(ext: string) {

}

draw_text_buffer :: proc() {
    buffer_lines := active_buffer.lines

    line_height := buffer_font_size * 1.2

    strings.builder_reset(&sb)
    strings.write_int(&sb, len(buffer_lines))

    highest_line_string := strings.to_string(sb)

    max_line_size := measure_text(buffer_font_size, highest_line_string)
    max_line_size.x += line_count_padding_px * 2

    active_buffer^.x_offset = (max_line_size.x) + (buffer_font_size * .5)

    add_rect(&rect_cache,
        rect{
            0,0,fb_size.x,fb_size.y,
        },
        no_texture,
        BG_MAIN_10,
        vec2{},
        -2,
    )

    if do_draw_line_count {
        add_rect(&rect_cache,
            rect{
                0,
                0 - buffer_scroll_position,
                max_line_size.x,
                f32(len(buffer_lines)) * (line_height),
            },
            no_texture,
            BG_MAIN_05,
            vec2{},
            4,
        )
    }

    line_buffer := make([dynamic]byte, len(buffer_lines))
    defer delete(line_buffer)
    
    pen := vec2{0,0}

    clear(&encountered_string_chars)
   
    error := ft.set_pixel_sizes(primary_font, 0, u32(buffer_font_size))
    assert(error == .Ok)

    ascender := f32(primary_font.size.metrics.ascender >> 6)
    descender := f32(primary_font.size.metrics.descender >> 6)

    char_map := get_char_map(buffer_font_size)

    for &buffer_line, index in buffer_lines {
        line_pos := vec2{
            pen.x - buffer_horizontal_scroll_position + active_buffer.x_offset,
            pen.y - buffer_scroll_position,
        }

        if line_pos.y > fb_size.y {
            break
        }

        pen = draw_buffer_line(
            &buffer_line,
            index,
            pen,
            &line_buffer,
            line_pos,
            ascender,
            descender,
            char_map,
            buffer_font_size,
        )
    }

    draw_rects(&rect_cache)
    reset_rect_cache(&rect_cache)

    /*
        TEXT, especially code text (which has unknown variable background colours)
        must be drawn on a separate pass, otherwise blending is not possible.
        thanks opengl
    */
    draw_rects(&text_rect_cache)
    reset_rect_cache(&text_rect_cache)
}

@(private="package")
open_file :: proc(file_name: string) {
    if active_buffer != nil {
        active_buffer^.cursor_char_index = buffer_cursor_char_index
        active_buffer^.cursor_line = buffer_cursor_line
        active_buffer^.scroll_position = buffer_scroll_position
        active_buffer^.horizontal_scroll_position = buffer_horizontal_scroll_position
    }

    existing_file : ^Buffer

    for buffer in buffers {
        if buffer.file_name == file_name {
            existing_file = buffer
            break
        }
    }

    if existing_file != nil {
        active_buffer = existing_file

        set_buffer_cursor_pos(
            existing_file.cursor_line,
            existing_file.cursor_char_index,
        )

        buffer_scroll_position = existing_file.scroll_position
        buffer_horizontal_scroll_position = existing_file.horizontal_scroll_position

        return
    }

    data, ok := os.read_entire_file_from_filename(file_name)

    if !ok {
        fmt.println("failed to open file")

        return
    }

    data_string := string(data)

    lines := strings.split(data_string, "\n")

    buffer_lines := new([dynamic]BufferLine)

    new_buffer := new(Buffer)
    new_buffer^.lines = buffer_lines
    new_buffer^.file_name = file_name

    new_buffer^.width = fb_size.x
    new_buffer^.height = fb_size.y
    new_buffer^.is_saved = true

    file_info, lstat_error := os.lstat(file_name)

    if lstat_error != os.General_Error.None {
        fmt.println("failed to lstat")

        return
    }

    new_buffer^.info = file_info
    new_buffer^.ext = filepath.ext(new_buffer^.file_name)

    active_buffer = new_buffer

    when ODIN_DEBUG {
        fmt.println("Validating buffer lines")
    }

    for line in lines { 
        runes := utf8.string_to_runes(line)
        
        buffer_line := BufferLine{
            characters=runes,
        }

        for r in line {
            get_char(buffer_font_size, u64(r))
        }

        set_line_word_defs(&buffer_line)

        append_elem(buffer_lines, buffer_line)
    }

    append(&buffers, new_buffer)

    when ODIN_DEBUG {
        fmt.println("Updating fonts for buffer")
    }

    set_buffer_cursor_pos(0,0)
    constrain_scroll_to_cursor()
}

remove_char_at_index :: proc(runes: []rune, index: int) -> []rune {
    if index < 0 || index >= len(runes) {
        return runes
    }

    new_runes := make([dynamic]rune, 0, len(runes) - 1)

    append_elems(&new_runes, ..runes[0:index])
    append_elems(&new_runes, ..runes[index+1:])

    active_buffer^.is_saved = false

    return new_runes[:]
}

insert_char_at_index :: proc(runes: []rune, index: int, c: rune) -> []rune {
    clamped_index := clamp(index, 0, len(runes))

    new_runes := make([dynamic]rune, 0, len(runes) + 1)
    
    append_elems(&new_runes, ..runes[0:clamped_index])
    append_elem(&new_runes, c)
    append_elems(&new_runes, ..runes[clamped_index:])

    active_buffer^.is_saved = false

    return new_runes[:]
}

insert_chars_at_index :: proc(runes: []rune, index: int, chars: []rune) -> []rune {
    clamped_index := clamp(index, 0, len(runes))

    new_runes := make([dynamic]rune, 0, len(runes) + 1)
    
    append_elems(&new_runes, ..runes[0:clamped_index])
    append_elems(&new_runes, ..chars[:])
    append_elems(&new_runes, ..runes[clamped_index:])

    active_buffer^.is_saved = false

    return new_runes[:]
}

close_file :: proc(file_name: string) -> (ok: bool) {
    return true
}

save_buffer :: proc() {
    buffer_to_save := make([dynamic]u8)
    defer delete(buffer_to_save)

    for line,index in active_buffer.lines {
        if index != 0 {
            append(&buffer_to_save, u8('\n'))
        }

        for character in line.characters {
            append(&buffer_to_save, u8(character))
        }
    }    

    ok := os.write_entire_file(
        active_buffer.file_name,
        buffer_to_save[:],
        true,
    )

    if !ok {
        panic("FAILED TO SAVE")
    }

    active_buffer^.is_saved = true
}

insert_tab_as_spaces:: proc() {
    line := &active_buffer.lines[buffer_cursor_line]

    tab_chars : []rune = {' ',' ',' ',' '}

    line^.characters = insert_chars_at_index(line.characters, buffer_cursor_char_index, tab_chars)

    set_buffer_cursor_pos(
        buffer_cursor_line,
        buffer_cursor_char_index+tab_spaces,
    )
}

remove_char :: proc() {
    line := &active_buffer.lines[buffer_cursor_line] 

    char_index := buffer_cursor_char_index

    if char_index > len(line.characters) {
        char_index = len(line.characters)
    }

    target := char_index - 1

    if target < 0 {
        if buffer_cursor_line == 0 {
            return
        }

        prev_line := &active_buffer.lines[buffer_cursor_line-1]
        prev_line_len := len(prev_line.characters)


        new_runes := make([dynamic]rune)
        
        append_elems(&new_runes, ..prev_line.characters)
        append_elems(&new_runes, ..line.characters)

        prev_line^.characters = new_runes[:]

        set_line_word_defs(prev_line)

        ordered_remove(active_buffer.lines, buffer_cursor_line)
        set_buffer_cursor_pos(buffer_cursor_line-1, prev_line_len)

        return
    }

    current_indent := get_line_indent_level(buffer_cursor_line) 

    if target < current_indent * tab_spaces {
        for i in 0..<tab_spaces {
            line^.characters = remove_char_at_index(line.characters, target-i)
        }

        set_line_word_defs(line)

        set_buffer_cursor_pos(
            buffer_cursor_line,
            char_index-tab_spaces,
        )

        return
    }

    line^.characters = remove_char_at_index(line.characters, target)

    set_line_word_defs(line)

    set_buffer_cursor_pos(buffer_cursor_line, target)
}

get_line_indent_level :: proc(line_num: int) -> int {
    line := active_buffer.lines[line_num]

    indent_spaces := 0

    for char in line.characters {
        if char != ' ' {
            break
        }

        indent_spaces += 1
    }

    indent_level := indent_spaces / tab_spaces

    return indent_level
}

determine_line_indent :: proc(line_num: int) -> int {
    if line_num == 0 {
        return 0
    }

    prev_line := active_buffer.lines[line_num-1]

    prev_line_indent_level := get_line_indent_level(line_num-1)

    length := len(prev_line.characters)

    if length == 0 {
        return 0
    }

    index := length - 1

    indent_runes := make([dynamic]rune)

    ext := filepath.ext(active_buffer.file_name)

    language_rules := indent_rule_language_list[ext]

    if language_rules == nil {
        return prev_line_indent_level * tab_spaces
    }

    prev_line_last_char := utf8.runes_to_string(prev_line.characters[index:index])
    defer delete(prev_line_last_char)

    if prev_line_last_char in language_rules {
        rule := language_rules[prev_line_last_char]

        if rule.type == .FORWARD {
            prev_line_indent_level += 1
        }       
    }

    return prev_line_indent_level*tab_spaces
}

@(private="package")
handle_text_input :: proc() -> bool {
    line := &active_buffer.lines[buffer_cursor_line] 
    
    char_index := buffer_cursor_char_index


    if is_key_pressed(glfw.KEY_ESCAPE) {
        input_mode = .COMMAND
    }

    if is_key_pressed(glfw.KEY_TAB) {
        insert_tab_as_spaces()

        set_line_word_defs(line)

        return false
    }

    if active_buffer == nil {
        return false
    }

    if is_key_pressed(glfw.KEY_BACKSPACE) {
        remove_char()

        return false
    } 

    if is_key_pressed(glfw.KEY_ENTER) {
        index := clamp(buffer_cursor_char_index, 0, len(line.characters))

        after_cursor := line.characters[index:]
        before_cursor := line.characters[:index] 

        line^.characters = before_cursor

        buffer_line := BufferLine{
            characters=after_cursor,
        }
        
        new_line_num := buffer_cursor_line+1

        indent_spaces := determine_line_indent(new_line_num)

        for i in 0..<indent_spaces {
            buffer_line.characters = insert_char_at_index(
                buffer_line.characters, 0, ' ',
            )
        }

        set_line_word_defs(line)
        set_line_word_defs(&buffer_line)

        inject_at(active_buffer.lines, new_line_num, buffer_line)

        set_buffer_cursor_pos(
            new_line_num,
            indent_spaces,
        )

        constrain_scroll_to_cursor()

        return false
    }

    return false
}

@(private="package") 
set_line_word_defs :: proc(line: ^BufferLine) {
    words := make([dynamic]WordDef)

    start_idx : int = -1

    for char,index in line.characters {
        if rune_in_arr(char, word_break_chars) == false {
            if start_idx < 0 {
                start_idx = index
            }

            continue
        }

        if start_idx < 0 {
            continue
        }

        word_def := new(WordDef)
        word_def^ = WordDef{
            start=i32(start_idx),
            end=i32(index),
        }

        set_word_color(word_def, line)

        append(&words, word_def^)

        start_idx = -1
    }

    if start_idx > -1 {
        word_def := new(WordDef)
        word_def^ = WordDef{
            start=i32(start_idx),
            end=i32(len(line.characters)),
        }

        set_word_color(word_def, line)

        append(&words, word_def^)
    }

    line.words = words[:]
}

set_word_color :: proc(word_def: ^WordDef, buffer_line: ^BufferLine) {
    word_runes := buffer_line.characters[word_def.start:word_def.end]
    word_string := utf8.runes_to_string(word_runes)

    keyword_list := keyword_language_list[active_buffer.ext]

    if keyword_list == nil {
        word_def^.color = TEXT_MAIN    

        return
    }

    for keyword,word_type in keyword_list {
        assert(word_type.match_proc != nil)

        does_match := word_type.match_proc(keyword, word_string, buffer_line)

        if does_match == false {
            continue
        }

        word_def^.color = word_type.color

        return
    }

    word_def^.color = TEXT_MAIN    
}

@(private="package")
insert_into_buffer :: proc (key: rune) {
    line := &active_buffer.lines[buffer_cursor_line] 
    
    line^.characters = insert_char_at_index(line.characters, buffer_cursor_char_index, key)

    get_char(buffer_font_size, u64(key))
    add_missing_characters()

    set_buffer_cursor_pos(buffer_cursor_line, buffer_cursor_char_index+1)

    constrain_scroll_to_cursor()

    set_line_word_defs(line)
}

constrain_scroll_to_cursor :: proc() {
    amnt_above_offscreen := (buffer_cursor_target_pos.y - buffer_scroll_position) - cursor_edge_padding + cursor_height

    if amnt_above_offscreen < 0 {
        buffer_scroll_position -= -amnt_above_offscreen 
    }

    amnt_below_offscreen := (buffer_cursor_target_pos.y - buffer_scroll_position) - (fb_size.y - cursor_edge_padding)

    if amnt_below_offscreen >= 0 {
        buffer_scroll_position += amnt_below_offscreen 
    }

    amnt_left_offscreen := (buffer_cursor_target_pos.x - buffer_horizontal_scroll_position)

    if amnt_left_offscreen < 0 {
        buffer_horizontal_scroll_position -= -amnt_left_offscreen 
    }

    amnt_right_offscreen := (buffer_cursor_target_pos.x - buffer_horizontal_scroll_position) - (fb_size.x - cursor_edge_padding)

    if amnt_right_offscreen >= 0 {
        buffer_horizontal_scroll_position += amnt_right_offscreen 
    }
}

move_up :: proc() {
    if buffer_cursor_line > 0 {
        set_buffer_cursor_pos(
            buffer_cursor_line-1,
            buffer_cursor_char_index,
        )
    }

    constrain_scroll_to_cursor()
}

move_left :: proc() {
    if buffer_cursor_char_index > 0 {
        line := active_buffer.lines[buffer_cursor_line]

        new := min(buffer_cursor_char_index - 1, len(line.characters)-1)

        set_buffer_cursor_pos(
            buffer_cursor_line,
            new,
        )
    }

    constrain_scroll_to_cursor()
}

move_right :: proc() {
    line := active_buffer.lines[buffer_cursor_line]

    if buffer_cursor_char_index < len(line.characters) {
        set_buffer_cursor_pos(
            buffer_cursor_line,
            buffer_cursor_char_index + 1,
        )
    }

    constrain_scroll_to_cursor()
}

move_down :: proc() {
    if buffer_cursor_line < len(active_buffer.lines) - 1 {
        new_index := buffer_cursor_line+1

        set_buffer_cursor_pos(
            new_index,
            buffer_cursor_char_index,
        )
    }

    constrain_scroll_to_cursor()
}

move_back_word :: proc() {
    line := active_buffer.lines[buffer_cursor_line]

    clamped_index := clamp(buffer_cursor_char_index, 0, len(line.characters))
    chars_before_cursor := line.characters[:clamped_index]
 
    new_char_index := clamped_index

    prev_was_break := false

    #reverse for r,index in chars_before_cursor {
        if index == 0 {
            new_char_index = 0
        }

        if rune_in_arr(r, word_break_chars) {
            new_char_index = index+1

            if new_char_index == buffer_cursor_char_index {
                new_char_index -= 1
            }

            break
        }
    }

    set_buffer_cursor_pos(
        buffer_cursor_line,
        new_char_index,
    )

    constrain_scroll_to_cursor()
}

move_forward_word :: proc() {
    line := active_buffer.lines[buffer_cursor_line]

    clamped_index := clamp(buffer_cursor_char_index, 0, len(line.characters))
    chars_after_cursor := line.characters[clamped_index:]

    new_char_index := clamped_index

    prev_was_space := false
    for r,index in chars_after_cursor {
        if index == len(chars_after_cursor) - 1 {
            new_char_index = index + buffer_cursor_char_index + 1
        }

        if rune_in_arr(r, word_break_chars) {
            if index == 0 {
                new_char_index = index + buffer_cursor_char_index + 1
            } else {
                new_char_index = index + buffer_cursor_char_index
            }

            break
        }
    }

    set_buffer_cursor_pos(
        buffer_cursor_line,
        new_char_index,
    )

    constrain_scroll_to_cursor()
}

scroll_down :: proc() {
    buffer_scroll_position += ((buffer_font_size * 1.2) * 80) * frame_time
}

scroll_up :: proc() {
    buffer_scroll_position -= ((buffer_font_size * 1.2) * 80) * frame_time
}

scroll_left :: proc() {
    buffer_horizontal_scroll_position = max(
        buffer_horizontal_scroll_position - ((buffer_font_size * 1.2) * 80) * frame_time,
        0
    )
}

scroll_right :: proc() {
    buffer_horizontal_scroll_position += ((buffer_font_size * 1.2) * 80) * frame_time
}

append_to_line :: proc() {
    line := active_buffer.lines[buffer_cursor_line]

    set_buffer_cursor_pos(
        buffer_cursor_line,
        len(line.characters)
    )

    input_mode = .BUFFER_INPUT
}

/*
@(private="package")
remove_selection :: proc(
    start_line: int,
    end_line: int,
    start_char: int,
    end_char: int,
) {
    start := start_line
    end := end_line

    is_negative_highlight := start_line >= end_line
    if is_negative_highlight {
        temp := start
        start = end
        end = temp
    }

    lines_to_remove : [dynamic]int

    for i in start..=end {
        line := &active_buffer.lines[i]

        if i == start && i == end {
            forward := start_char <= end_char

            clamped_end := min(end_char, len(line.characters))
            clamped_start := min(start_char, len(line.characters))

            if forward {
                before := line.characters[:clamped_start]
                after := line.characters[clamped_end:]

                new_runes := new([dynamic]rune)

                append_elems(new_runes, ..before)
                append_elems(new_runes, ..after)

                fmt.println(before, after, i)

                line^.characters = new_runes^[:]
            } else {
                line^.characters = line.characters[clamped_end:clamped_start]
            }
        } else if i == end {
            if is_negative_highlight {
                if len(line.characters) == 0 {
                    ordered_remove(active_buffer.lines, i)
                } else {
                    clamped := min(start_char, len(line.characters))

                    if clamped == len(line.characters) {
                        append(&lines_to_remove, i)
                    } else {
                        line^.characters = line.characters[clamped:]
                    }
                }
            } else {
                if len(line.characters) == 0 {
                    append(&lines_to_remove, i)
                } else {
                    clamped := min(end_char, len(line.characters))

                    if clamped == len(line.characters) {
                        append(&lines_to_remove, i)
                    } else {
                        line^.characters = line.characters[clamped:]
                    }
                }
            }
        } else if i == start {
            if is_negative_highlight {
                if len(line.characters) == 0 {
                    append(&lines_to_remove, i)
                } else {
                    clamped := clamp(end_char, 0, len(line.characters))

                    if clamped == len(line.characters) {
                        append(&lines_to_remove, i)
                    } else {
                        line^.characters = line.characters[:clamped]
                    }
                }
            } else {
                if len(line.characters) == 0 {
                    append(&lines_to_remove, i)
                } else {
                    clamped := clamp(start_char, 0, len(line.characters))

                    if clamped == len(line.characters) {
                        append(&lines_to_remove, i)
                    } else {
                        line^.characters = line.characters[:clamped]
                    }
                }
            }
        } else {
            append(&lines_to_remove, i)
        }
    }

    set_buffer_cursor_pos(
        start_line,
        start_char,
    )
}
*/

@(private="package")
remove_selection :: proc(
    start_line: int, end_line: int,
    start_char: int, end_char: int,
) {
    a_line, a_char := start_line, start_char
    b_line, b_char := end_line,   end_char
    if a_line > b_line || (a_line == b_line && a_char > b_char) {
        a_line, b_line = b_line, a_line
        a_char, b_char = b_char, a_char
    }

    lines_to_remove := [dynamic]int{}

    if a_line == b_line {
        line := &active_buffer.lines[a_line]
        s := min(a_char, len(line.characters))
        e := min(b_char, len(line.characters))
        new_chars := [dynamic]rune{}
        runtime.append_elems(&new_chars, ..line.characters[:s])
        runtime.append_elems(&new_chars, ..line.characters[e:])

        line^.characters = new_chars[:]

        set_buffer_cursor_pos(a_line, a_char)
        return
    }

    for i in a_line..=b_line {
        line := &active_buffer.lines[i]
        count := len(line.characters)
        s := min(a_char, count)
        e := min(b_char, count)

        if i == a_line {
            if s == 0 {
                runtime.append_elem(&lines_to_remove, i)
            } else {
                line.characters = line.characters[:s]
            }

        } else if i == b_line {
            if e == count {
                runtime.append_elem(&lines_to_remove, i)
            } else {
                line.characters = line.characters[e:]
            }

        } else {
            runtime.append_elem(&lines_to_remove, i)
        }
    }
    
    j := len(lines_to_remove)
    for j > 0 {
        j -= 1
        ordered_remove(active_buffer.lines, lines_to_remove[j])
    }

    set_buffer_cursor_pos(a_line, a_char)
}



@(private="package")
handle_buffer_input :: proc() -> bool {
    if is_key_pressed(glfw.KEY_S) {
        key := key_store[glfw.KEY_S]

        if key.modifiers == 2 {
            save_buffer()
        }

        return false
    }

    if is_key_pressed (glfw.KEY_R) {
        // add reload logic
    }


    if is_key_pressed(glfw.KEY_Z) {
        key := key_store[glfw.KEY_Z]

        set_buffer_cursor_pos(
            key.modifiers == 1 ? 0 : buffer_cursor_line,
            0,
        )
    }

    if is_key_pressed(glfw.KEY_V) {
        input_mode = .HIGHLIGHT

        highlight_start_line = buffer_cursor_line 
        highlight_start_char = buffer_cursor_char_index

        return true
    }

    if is_key_pressed(glfw.KEY_P) {
        //key := key_store[glfw.KEY_P]

        paste_string(yank_buffer.data[0], buffer_cursor_line, buffer_cursor_char_index)

        return false
    }

    if is_key_pressed(glfw.KEY_G) {
        de := os.get_env("XDG_CURRENT_DESKTOP") 

        if de == "GNOME" {
            glfw.WaitEvents()
        }

        delete(de)

        input_mode = .SEARCH

        return false
    }

    if is_key_pressed(glfw.KEY_MINUS) {
        buffer_font_size = clamp(buffer_font_size+1, buffer_font_size, 100)

        update_fonts()

        constrain_scroll_to_cursor()

        set_buffer_cursor_pos(
            buffer_cursor_line,
            buffer_cursor_char_index,
        )

        return false
    }

    if is_key_pressed(glfw.KEY_SLASH) {
        buffer_font_size = clamp(buffer_font_size-1, 8, buffer_font_size)

        update_fonts()

        constrain_scroll_to_cursor()

        set_buffer_cursor_pos(
            buffer_cursor_line,
            buffer_cursor_char_index,
        )

        return false
    }

    if is_key_pressed(glfw.KEY_A) {
        line := active_buffer.lines[buffer_cursor_line]

        set_buffer_cursor_pos(
            buffer_cursor_line,
            len(line.characters),
        )

        return true
    }

    if is_key_pressed(glfw.KEY_I) {
        de := os.get_env("XDG_CURRENT_DESKTOP") 

        if de == "GNOME" {
            glfw.WaitEvents()
        }

        delete(de)

        input_mode = .BUFFER_INPUT

        return false
    }

    if is_key_pressed(glfw.KEY_M) {
        prev_buffer()

        return false
    }

    if is_key_pressed(glfw.KEY_COMMA) {
        next_buffer()

        return false
    }

    handle_movement_input()

    if is_key_pressed(glfw.KEY_Q) {
        toggle_buffer_info_view()

        return false
    }

    if is_key_pressed(glfw.KEY_1) {
        set_buffer(1)
    }

    if is_key_pressed(glfw.KEY_2) {
        set_buffer(2)
    }

    if is_key_pressed(glfw.KEY_3) {
        set_buffer(3)
    }
 
    if is_key_pressed(glfw.KEY_4) {
        set_buffer(4)
    }
  
    if is_key_pressed(glfw.KEY_5) {
        set_buffer(5)
    }
  
    if is_key_pressed(glfw.KEY_6) {
        set_buffer(6)
    }
  
    if is_key_pressed(glfw.KEY_7) {
        set_buffer(7)
    }
  
    if is_key_pressed(glfw.KEY_8) {
        set_buffer(8)
    }
  
    if is_key_pressed(glfw.KEY_9) {
        set_buffer(9)
    }
  
    if is_key_pressed(glfw.KEY_0) {
        set_buffer(10)
    }
 
    return false
}

@(private="package")
paste_string :: proc(str: string, line: int, char: int) {
    split := strings.split(str, "\n")

    defer delete(split)

    buffer_line := &active_buffer.lines[line]

    if len(split) == 1 {
        runes := utf8.string_to_runes(str)

        buffer_line^.characters = insert_chars_at_index(buffer_line.characters, char, runes)

        set_buffer_cursor_pos(
            line,
            buffer_cursor_char_index + len(str),
        )

        return
    }


    clamped := clamp(char, 0, len(buffer_line.characters))

    prev := buffer_line.characters[:clamped]
    after := buffer_line.characters[clamped:]

    /*
    for i in 0..<len(split) {
        line_index := line + i

        if line_index == line {
                        continue
        }

        runes := utf8.string_to_runes(split[i])

        buffer_line := BufferLine{
            characters=runes,
        }

        if i == len(split) - 1 {
            buffer_line.characters = insert_chars_at_index(buffer_line.characters, len(runes), after)
        }

        new_line_num := buffer_cursor_line+1

        set_line_word_defs(&buffer_line)

        inject_at(active_buffer.lines, new_line_num, buffer_line)

        constrain_scroll_to_cursor()

        if i == len(split) - 1 {
            set_buffer_cursor_pos(
                new_line_num,
                len(runes),
            )
        }
    }
    */

    for i in 0..<len(split) {
        line_index := line + i

        if i == 0 {
            runes := utf8.string_to_runes(split[i])
            
            buffer_line^.characters = prev
            buffer_line^.characters = insert_chars_at_index(buffer_line.characters, char, runes)


            continue
        }

        // for each subsequent fragment, insert at exactly line + i
        runes := utf8.string_to_runes(split[i])
        inserted := BufferLine{ characters = runes }

        if i == len(split)-1 {
            // append the ‘after’ suffix on the last fragment
            inserted.characters = insert_chars_at_index(runes, len(runes), after)
        }

        set_line_word_defs(&inserted)
        inject_at(active_buffer.lines, line_index, inserted)
        constrain_scroll_to_cursor()

        if i == len(split)-1 {
            set_buffer_cursor_pos(line_index, len(runes))
        }
    }

}

@(private="package")
handle_movement_input :: proc() -> bool {
    if is_key_down(glfw.KEY_J) {
        key := key_store[glfw.KEY_J]

        if key.modifiers == 1 {
            scroll_down()

            return false
        }
    }

    if is_key_pressed(glfw.KEY_J) {
        move_down()

        return false
    }

    if is_key_down(glfw.KEY_K) {
        key := key_store[glfw.KEY_K]

        if key.modifiers == 1 {
            scroll_up()

            return false
        }
    }

    if is_key_pressed(glfw.KEY_K) {
        move_up()

        return false
    }

    if is_key_down(glfw.KEY_D) {
        key := key_store[glfw.KEY_D]

        if key.modifiers == 1 {
            scroll_left()

            return false
        }
    }

    if is_key_pressed(glfw.KEY_D) {
        move_left()

        return false
    }

    if is_key_down(glfw.KEY_F) {
        key := key_store[glfw.KEY_F]

        if key.modifiers == 1 {
            scroll_right()

            return false
        }
    }

    if is_key_pressed(glfw.KEY_F) {
        move_right()

        return false
    }

    if is_key_pressed(glfw.KEY_R) {
        move_back_word()

        return false
    }

    if is_key_pressed(glfw.KEY_U) {
        move_forward_word()

        return false
    }

    return false
}

@(private="package")
buffer_append_to_search_term :: proc(key: rune) {
    buf := make([dynamic]rune)

    runes := utf8.string_to_runes(buffer_search_term)
    
    append_elems(&buf, ..runes)
    append_elem(&buf, key)

    buffer_search_term = utf8.runes_to_string(buf[:])
}

@(private="package")
handle_search_input :: proc() {
    if is_key_pressed(glfw.KEY_ESCAPE) {
        buffer_search_term = ""

        selected_hit = nil

        clear(&search_hits)

        input_mode = .COMMAND

        return
    }

    if is_key_pressed(glfw.KEY_BACKSPACE) {
        runes := utf8.string_to_runes(buffer_search_term)

        end_idx := len(runes)-1        

        runes = runes[:end_idx]

        buffer_search_term = utf8.runes_to_string(runes)

        delete(runes)
    }

    if is_key_pressed(glfw.KEY_ENTER) {
        selected_hit = nil

        find_hits()

        return
    }

    if is_key_pressed(glfw.KEY_J) {
        key := key_store[glfw.KEY_J]

        if key.modifiers == 2 {
            set_hit_index(hit_index + 1)
        }

        return
    }

    if is_key_pressed(glfw.KEY_K) {
        key := key_store[glfw.KEY_K]

        if key.modifiers == 2 {
            set_hit_index(hit_index - 1)
        }

        return
    }

    if is_key_pressed(glfw.KEY_V) && selected_hit != nil {
        input_mode = .HIGHLIGHT

        highlight_start_line = selected_hit.line
        highlight_start_char = selected_hit.start_char

        set_buffer_cursor_pos(
            buffer_cursor_line,
            selected_hit.end_char
        )

        selected_hit = nil

        return
    }

}
