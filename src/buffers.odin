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
    
import ts "../../odin-tree-sitter"
    
@(private="package")
BufferLine :: struct {
    characters: []rune,
}

@(private="package")
BufferError :: struct {
    line: int,
    error_string: string,
}

@(private="package")
buffer_errors : [dynamic]BufferError = {}

@(private="package")
Buffer :: struct {
    lines: ^[dynamic]BufferLine,
    
    // Unused(?)
    x_offset: f32,

    // Unused
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
    
    // Used for LSP stuff
    version: int,

    // Syntax highlighting
    tokens: [dynamic]Token,
    new_tokens : [dynamic]Token,
    did_tokens_update : bool,
    
    token_set_id: string,
    
    // Raw LSP syntax highlihgting tokens
    raw_token_data: [dynamic]i32,
    
    // Tree-sitter tree
    previous_tree: ts.Tree,
    
    // Raw data that we read from file and modify for tree-sitter so it doesnt die
    content: []u8,
    
    query: ts.Query,
    
    first_drawn_line: int,
    last_drawn_line: int,
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

@(private="package")
do_refresh_buffer_tokens := false

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

@(private="package")
find_search_hits :: proc() {
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
        
        if idx > len(search_hits) - 1 {
            return
        }
    } else if idx == -1 {
        idx = len(search_hits) - 1
        
        if idx == -1 {
            return
        }
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
    buffer: ^Buffer,
    buffer_line: ^BufferLine,
    index: int,
    input_pen: vec2,
    line_buffer: ^[dynamic]byte,
    line_pos: vec2,
    ascender: f32,
    descender: f32,
    char_map: ^CharacterMap,
    font_size: f32,

    token_idx: ^int,
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
        buffer,
        token_idx,
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
    if active_buffer.did_tokens_update == true {
        active_buffer.tokens = active_buffer.new_tokens
    }
    
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

    error := ft.set_pixel_sizes(primary_font, 0, u32(buffer_font_size))
    assert(error == .Ok)

    ascender := f32(primary_font.size.metrics.ascender >> 6)
    descender := f32(primary_font.size.metrics.descender >> 6)

    char_map := get_char_map(buffer_font_size)

    token_idx := new(int)

    active_buffer.first_drawn_line = -1
    active_buffer.last_drawn_line = -1

    for &buffer_line, index in buffer_lines {
        line_pos := vec2{
            pen.x - buffer_horizontal_scroll_position + active_buffer.x_offset,
            pen.y - buffer_scroll_position,
        }

        if line_pos.y > fb_size.y {
            active_buffer.last_drawn_line = index
            break
        }
        
        if line_pos.y < 0 {
            pen.y += ascender - descender
            continue
        }
        
        if active_buffer.first_drawn_line == -1 {
            active_buffer.first_drawn_line = index
        }

        pen = draw_buffer_line(
            active_buffer,
            &buffer_line,
            index,
            pen,
            &line_buffer,
            line_pos,
            ascender,
            descender,
            char_map,
            buffer_font_size,
            token_idx,
        )
    }
    
    free(token_idx)

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
    
    content := make([dynamic]u8, len(data))
    copy(content[:], data)
    
    new_buffer^.content = content[:]

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
    
    when ODIN_DEBUG {
        fmt.println("Finished creating a buffer.", new_buffer)
    }

    for line in lines { 
        runes := utf8.string_to_runes(line)
        
        buffer_line := BufferLine{
            characters=runes,
        }

        for r in line {
            get_char(buffer_font_size, u64(r))
        }

        append_elem(buffer_lines, buffer_line)
    }

    append(&buffers, new_buffer)
    
    set_buffer_cursor_pos(0,0)
    constrain_scroll_to_cursor()
    
    lsp_handle_file_open()
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
    buffer_to_close : ^Buffer
    
    for buffer in buffers {
    
    }
    return true
}

/*
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
*/

save_buffer :: proc() {
    buffer_to_save := make([dynamic]u8)
    defer delete(buffer_to_save)

    for line, index in active_buffer.lines {
        if index != 0 {
            append(&buffer_to_save, '\n');
        }

        for character in line.characters {
            encoded, size := utf8.encode_rune(character);
            append_elems(&buffer_to_save, ..encoded[0:size]);
        }
    }

    ok := os.write_entire_file(
        active_buffer.file_name,
        buffer_to_save[:],
        true,
    );

    if !ok {
        panic("FAILED TO SAVE");
    }

    active_buffer^.is_saved = true;
}


insert_tab_as_spaces:: proc() {
    line := &active_buffer.lines[buffer_cursor_line]

    tab_chars : []rune = {' ',' ',' ',' '}

    old_length := len(line.characters)
    old_byte_length := len(utf8.runes_to_string(line.characters))
    line^.characters = insert_chars_at_index(line.characters, buffer_cursor_char_index, tab_chars)
    
    notify_server_of_change(
        active_buffer,
        buffer_cursor_line,
        0,
        buffer_cursor_line,
        old_length,
        old_byte_length,
        len(line.characters),
        utf8.runes_to_string(line.characters[:])
    )

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
        old_byte_length := len(utf8.runes_to_string(prev_line.characters))

        new_runes := make([dynamic]rune)
        
        append_elems(&new_runes, ..prev_line.characters)
        append_elems(&new_runes, ..line.characters)

        prev_line^.characters = new_runes[:]

        new_text := strings.clone(utf8.runes_to_string(prev_line.characters[:]))
        
        ordered_remove(active_buffer.lines, buffer_cursor_line)
     
        notify_server_of_change(
            active_buffer,
            buffer_cursor_line - 1,
            prev_line_len,
            buffer_cursor_line,
            0,
            1,
            prev_line_len,
            "",
        )
        
        set_buffer_cursor_pos(buffer_cursor_line-1, prev_line_len)
        
        return
    }

    current_indent := get_line_indent_level(buffer_cursor_line) 

    if target < current_indent * tab_spaces {
        for i in 0..<tab_spaces {
            line^.characters = remove_char_at_index(line.characters, target-i)
        }

        set_buffer_cursor_pos(
            buffer_cursor_line,
            char_index-tab_spaces,
        )

        return
    }

    old_line_length := len(line.characters)
    old_byte_length := len(utf8.runes_to_string(line.characters))
    
    line^.characters = remove_char_at_index(line.characters, target)
    
    notify_server_of_change(
        active_buffer,
        buffer_cursor_line,
        0,
        buffer_cursor_line,
        old_line_length,
        old_byte_length,
        len(line.characters),
        utf8.runes_to_string(line.characters[:]),
    )

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
        fmt.println("hi")
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
        
        old_line_length := len(line.characters)
        old_byte_length := len(utf8.runes_to_string(line.characters))
        
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
        
        inject_at(active_buffer.lines, new_line_num, buffer_line)
        
        new_text := strings.concatenate({
            utf8.runes_to_string(before_cursor),
            "\n",
            utf8.runes_to_string(buffer_line.characters),
        })
        
        notify_server_of_change(
            active_buffer,
            buffer_cursor_line,
            0,
            buffer_cursor_line,
            old_line_length,
            old_byte_length,
            len(before_cursor),
            new_text,
        )
        
        delete(new_text)
        
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
insert_into_buffer :: proc (key: rune) {
    line := &active_buffer.lines[buffer_cursor_line] 
    
    old_length := len(line.characters)
    old_byte_length := len(utf8.runes_to_string(line.characters[:]))

    line^.characters = insert_char_at_index(line.characters, buffer_cursor_char_index, key)

    get_char(buffer_font_size, u64(key))
    add_missing_characters()

    set_buffer_cursor_pos(buffer_cursor_line, buffer_cursor_char_index+1)

    constrain_scroll_to_cursor()
    
    notify_server_of_change(
        active_buffer,
        buffer_cursor_line,
        0,
        buffer_cursor_line,
        old_length,
        old_byte_length,
        len(line.characters),
        utf8.runes_to_string(line.characters[:]),
    )
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

@(private="package")
indent_selection :: proc(start_line: int, end_line: int) {
    start_line : int = start_line
    end_line : int = end_line
    
    if end_line < start_line {
        temp := end_line
        end_line = start_line
        start_line = temp
    }
    
    chars := []rune{' ', ' ', ' ', ' '}
    text := ""
    old_bytes := 0

    for i in start_line..=end_line {
        line := &active_buffer.lines[i]
        old_line_str := utf8.runes_to_string(line.characters)
        old_bytes += len(old_line_str)

        line^.characters = insert_chars_at_index(line.characters, 0, chars)

        new_line_str := utf8.runes_to_string(line.characters)
        
        text = strings.concatenate({text, new_line_str})
        if i < end_line {
            text = strings.concatenate({text, "\n"})
            old_bytes += 1
        }
    }

    notify_server_of_change(
        active_buffer,
        start_line, 0,
        end_line, len(utf8.runes_to_string(active_buffer.lines[end_line].characters)) - len(chars),
        old_bytes,
        len(utf8.runes_to_string(active_buffer.lines[end_line].characters)),
        text,
    )
}

array_is_equal :: proc(a, b: []rune) -> bool {
    if len(a) != len(b) {
        return false
    }
    for i in 0..<len(a) {
        if a[i] != b[i] {
            return false
        }
    }
    return true
}

@(private="package")
unindent_selection :: proc(start_line: int, end_line: int) {
    start_line : int = start_line
    end_line : int = end_line
    
    if end_line < start_line {
        temp := end_line
        end_line = start_line
        start_line = temp
    }
    
    chars := []rune{' ', ' ', ' ', ' '}
    lines := active_buffer.lines

    old_lines := make([dynamic][]rune)
    old_bytes := 0
    for i in start_line..=end_line {
        old := lines[i].characters[:]
        append(&old_lines, old)
        old_str := utf8.runes_to_string(old)
        old_bytes += len(old_str)
        if i < end_line {
            old_bytes += 1
        }
    }

    text := ""
    for idx in 0..<len(old_lines) {
        old := old_lines[idx]
        count := 0
        for count < len(chars) && count < len(old) && old[count] == ' ' {
            count += 1
        }
        lines[start_line + idx].characters = old[count:]

        new_str := utf8.runes_to_string(lines[start_line + idx].characters)
        if text == "" {
            text = new_str
        } else {
            text = strings.concatenate({text, "\n", new_str})
        }
    }

    old_last_len := len(old_lines[end_line - start_line])
    new_last_len := len(lines[end_line].characters)

    notify_server_of_change(
        active_buffer,
        start_line,
        0,
        end_line,
        old_last_len,
        old_bytes,
        new_last_len,
        text,
    )
    
    cursor_line := lines[buffer_cursor_line]
    if buffer_cursor_char_index > len(cursor_line.characters) {
        set_buffer_cursor_pos(
            buffer_cursor_line,
            len(cursor_line.characters),
        )
    }
}

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

    if len(active_buffer.lines) == 0 {
        append(active_buffer.lines, BufferLine{})
    }

    set_buffer_cursor_pos(a_line, a_char)
}

delete_line :: proc(line: int) {
    ordered_remove(active_buffer.lines, line)
    
    if len(active_buffer.lines) == 0 {
        append(active_buffer.lines, BufferLine{})
    }

    notify_server_of_change(
        active_buffer,
        buffer_cursor_line,
        0,
        buffer_cursor_line+1,
        0,
        0,
        0,
        "",
    )

    // edge case for deleting the last line
    if buffer_cursor_line > len(active_buffer.lines) - 1 {
        set_buffer_cursor_pos(
            buffer_cursor_line - (buffer_cursor_line - (len(active_buffer.lines)-1)),
            buffer_cursor_char_index,
        )
    }
    
    new_line := active_buffer.lines[buffer_cursor_line]
    
    new_line_size := len(new_line.characters)
    
    if buffer_cursor_char_index > new_line_size {
        set_buffer_cursor_pos(
            buffer_cursor_line,
            new_line_size,
        )
    }
}

inject_line :: proc() {   
    buffer_line := BufferLine{}
        
    indent_spaces := determine_line_indent(buffer_cursor_line + 1)

    for i in 0..<indent_spaces {
        buffer_line.characters = insert_char_at_index(
            buffer_line.characters, 0, ' ',
        )  
    }

    old_line := active_buffer.lines[buffer_cursor_line]
    old_line_length := len(old_line.characters)
    old_byte_length := len(utf8.runes_to_string(old_line.characters))

    new_text := strings.concatenate({
        "\n", strings.repeat(" ", indent_spaces),
    })

    notify_server_of_change(
        active_buffer,
        buffer_cursor_line,
        old_line_length,
        buffer_cursor_line,
        old_line_length,
        old_byte_length,
        len(old_line.characters),
        new_text,
    )

    fmt.println(new_text)
     
    inject_at(active_buffer.lines, buffer_cursor_line + 1, buffer_line)

    set_buffer_cursor_pos(
        buffer_cursor_line + 1,
        indent_spaces, 
    )

    de := os.get_env("XDG_CURRENT_DESKTOP") 

    if de == "GNOME" {
        glfw.WaitEvents()
    }

    delete(de)
    
    input_mode = .BUFFER_INPUT
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

    if is_key_pressed(glfw.KEY_W) {
        if key_store[glfw.KEY_W].modifiers == CTRL_SHIFT {
            close_buffer(active_buffer)
        }
    }

    if is_key_pressed(glfw.KEY_C) {
        key := key_store[glfw.KEY_C]

        if key.modifiers == SHIFT {
            delete_line(buffer_cursor_line)
        }
    }
    
    if is_key_pressed(glfw.KEY_L) {
        inject_line()
    }

    if is_key_pressed(glfw.KEY_V) {
        input_mode = .HIGHLIGHT

        highlight_start_line = buffer_cursor_line 
        highlight_start_char = buffer_cursor_char_index

        return true
    }

    if is_key_pressed(glfw.KEY_P) {
        key := key_store[glfw.KEY_P]

        if key.modifiers == 2 {
            paste_string(glfw.GetClipboardString(window), buffer_cursor_line, buffer_cursor_char_index)
        } else {
            paste_string(yank_buffer.data[0], buffer_cursor_line, buffer_cursor_char_index)
        }

        return false
    }

    if is_key_pressed(glfw.KEY_G) {
        de := os.get_env("XDG_CURRENT_DESKTOP") 

        if de == "GNOME" {
            glfw.WaitEvents()
        }

        delete(de)

        input_mode = .SEARCH
        
        cached_buffer_cursor_line = buffer_cursor_line
        cached_buffer_cursor_char_index = buffer_cursor_char_index

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
close_buffer :: proc(buf: ^Buffer) {
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

    for i in 0..<len(split) {
        line_index := line + i

        if i == 0 {
            runes := utf8.string_to_runes(split[i])
            
            buffer_line^.characters = prev
            buffer_line^.characters = insert_chars_at_index(buffer_line.characters, char, runes)


            continue
        }

        runes := utf8.string_to_runes(split[i])
        inserted := BufferLine{ characters = runes }

        if i == len(split)-1 {
            inserted.characters = insert_chars_at_index(runes, len(runes), after)
        }

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

        if key.modifiers == SHIFT {
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

        if key.modifiers == SHIFT {
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

        if key.modifiers == SHIFT {
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

        if key.modifiers == SHIFT {
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
    
    if is_key_pressed(glfw.KEY_A) {
        key := key_store[glfw.KEY_A]
        
        if key.modifiers == SHIFT {
            set_buffer_cursor_pos(
                len(active_buffer.lines) - 1,
                buffer_cursor_char_index,
            )
            
            constrain_scroll_to_cursor()
        
            return true
        }
        
        
        line := active_buffer.lines[buffer_cursor_line]

        set_buffer_cursor_pos(
            buffer_cursor_line,
            len(line.characters),
        )
        
        constrain_scroll_to_cursor()

        return true
    }
    
    if is_key_pressed(glfw.KEY_Z) {
        key := key_store[glfw.KEY_Z]

        set_buffer_cursor_pos(
            key.modifiers == SHIFT ? 0 : buffer_cursor_line,
            0,
        )
        
        constrain_scroll_to_cursor()
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

cached_buffer_cursor_line : int = -1
cached_buffer_cursor_char_index : int = -1

@(private="package")
handle_search_input :: proc() {
    if is_key_pressed(glfw.KEY_ESCAPE) {
        buffer_search_term = ""

        selected_hit = nil

        clear(&search_hits)

        input_mode = .COMMAND
        
        cached_buffer_cursor_line = -1
        cached_buffer_cursor_char_index = -1

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

        find_search_hits()

        return
    }
    
    if is_key_pressed(glfw.KEY_B) {
        key := key_store[glfw.KEY_B]
        
        if key.modifiers != CTRL {
            return
        }
        
        buffer_search_term = ""

        selected_hit = nil

        clear(&search_hits)

        input_mode = .COMMAND
        
        set_buffer_cursor_pos(
            cached_buffer_cursor_line,
            cached_buffer_cursor_char_index,
        )
        
        constrain_scroll_to_cursor()
        
        cached_buffer_cursor_line = -1
        cached_buffer_cursor_char_index = -1

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

@(private="package")
serialize_buffer :: proc(buffer: ^Buffer) -> string {
    buffer_to_save := make([dynamic]u8)
    defer delete(buffer_to_save)

    for line, index in active_buffer.lines {
        if index != 0 {
            append(&buffer_to_save, '\n');
        }

        for character in line.characters {
            encoded, size := utf8.encode_rune(character);
            append_elems(&buffer_to_save, ..encoded[0:size]);
        }
    }
    
    return strings.clone(string(buffer_to_save[:]))
}

@(private="package")
escape_json :: proc(text: string) -> string {
    builder := strings.builder_make()
    
    for c in text {
        switch c {
        case '"':
            strings.write_string(&builder, "\\\"")
        case '\\':
            strings.write_string(&builder, "\\\\")
        case '\b':
            strings.write_string(&builder, "\\b")
        case '\f':
            strings.write_string(&builder, "\\f")
        case '\n':
            strings.write_string(&builder, "\\n")
        case '\r':
            strings.write_string(&builder, "\\r")
        case '\t':
            strings.write_string(&builder, "\\t")
        case:
            strings.write_rune(&builder, c)
        }
    }

    return strings.clone(strings.to_string(builder))
}
