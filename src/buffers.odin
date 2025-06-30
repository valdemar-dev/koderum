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
import "core:encoding/json"
import "core:path/filepath"
import ft "../../alt-odin-freetype" 
import ts "../../odin-tree-sitter"    
import "core:time"
import "core:math"
import "core:thread"

@(private="package")
BufferLine :: struct {
    characters: [dynamic]u8,
    tokens : [dynamic]Token,
    errors : [dynamic]BufferError,
}

@(private="package")
BufferError :: struct {
    source: string,
    message: string,
    severity: int,

    char: int,
    width: int,
}

@(private="package")
CompletionHit :: struct {
    label: string,
    kind: int,
    detail: string,
    documentation: string,
    insertText: string,
    insertTextFormat: int,

    raw_data: string,
}

@(private="package")
completion_hits : [dynamic]CompletionHit = {}

@(private="package")
selected_completion_hit : int

@(private="package")
is_incomplete_completion_list := false

@(private="package")
completion_filter_token : string

@(private="package")
cached_buffer_cursor_line : int = -1

@(private="package")
cached_buffer_cursor_char_index : int = -1

@(private="package")
cached_buffer_index : int = -1

@(private="package")
Buffer :: struct {
    lines: ^[dynamic]BufferLine,

    offset_x: f32,

    scroll_x: f32,
    scroll_y: f32,
    
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
    version: int,
    tokens: [dynamic]Token,
    previous_tree: ts.Tree,
    content: [dynamic]u8,
    query: ts.Query,
    first_drawn_line: int,
    last_drawn_line: int,

    redo_stack: [dynamic]BufferChange,
    undo_stack: [dynamic]BufferChange,
}

@(private="package")
BufferChange :: struct {
    start_byte: u32,
    end_byte: u32,

    start_line: int,
    start_char: int,

    end_line: int,
    end_char: int,

    original_content: []u8,
    new_content: []u8,
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
do_refresh_buffer_tokens := false

sb := strings.builder_make()

SearchHit :: struct{
    line: int,
    start_char: int,
    end_char: int,
}

@(private="package")
search_hits : [dynamic]SearchHit

@(private="package")
selected_hit: ^SearchHit

@(private="package")
buffer_search_term : string

undo_change :: proc() {
    if len(active_buffer.undo_stack) == 0 {
        return
    }

    idx := len(active_buffer.undo_stack)-1
    change := active_buffer.undo_stack[idx]

    // gotta recompute
    end,end_byte := byte_to_pos(change.start_byte + u32(len(change.new_content)))

    end_rune := byte_offset_to_rune_index(
        string(active_buffer.lines[end].characters[:]),
        int(end_byte),
    )

    remove_range(
        &active_buffer.content,
        change.start_byte,
        change.start_byte + u32(len(change.new_content)),
    )

    inject_at(&active_buffer.content, change.start_byte, ..change.original_content) 

    ordered_remove(&active_buffer.undo_stack, idx)
    append(&active_buffer.redo_stack, change)

    update_buffer_lines_after_change(active_buffer, change, true)

    notify_server_of_change(
        active_buffer,
        int(change.start_byte),
        int(change.start_byte + u32(len(change.new_content))),
        change.start_line,
        change.start_char,
        end,
        end_rune,
        change.original_content,
        false
    )

    set_buffer_cursor_pos(
        change.start_line,
        change.end_char,
    )
}

redo_change :: proc() {
    if len(active_buffer.redo_stack) == 0 {
        return
    }

    idx := len(active_buffer.redo_stack)-1
    change := active_buffer.redo_stack[idx]

    remove_range(
        &active_buffer.content,
        change.start_byte,
        change.start_byte + u32(len(change.original_content)),
    )

    inject_at(&active_buffer.content, change.start_byte, ..change.new_content) 

    ordered_remove(&active_buffer.redo_stack, idx)
    append(&active_buffer.undo_stack, change)

    update_buffer_lines_after_change(active_buffer, change, false)

    notify_server_of_change(
        active_buffer,
        int(change.start_byte),
        int(change.end_byte),
        change.start_line,
        change.start_char,
        change.end_line,
        change.end_char,
        change.new_content,
        false
    )

    set_buffer_cursor_pos(
        change.start_line,
        change.end_char,
    )
}

update_buffer_lines_after_change :: proc(buffer: ^Buffer, change: BufferChange, is_undo:bool) {
    start_byte := change.start_byte

    text := is_undo ? change.original_content : change.new_content

    remove_size := is_undo ? len(change.new_content) : len(change.original_content)

    end_byte := change.start_byte + u32(remove_size)

    a_line, a_char := byte_to_pos(start_byte)
    b_line, b_char := byte_to_pos(end_byte)

    if a_line > b_line || (a_line == b_line && a_char > b_char) {
        a_line, b_line = b_line, a_line
        a_char, b_char = b_char, a_char
    }

    start_accumulated := compute_byte_offset(
        active_buffer, 
        int(a_line),
        int(a_char),
    )

    end_accumulated := compute_byte_offset(
        active_buffer, 
        int(b_line),
        int(b_char),
    )

    if a_line == b_line {
        target_line := &active_buffer.lines[a_line]
        remove_range(&target_line.characters, a_char, b_char)
    } else {
        first_line := &active_buffer.lines[a_line]
        last_line := &active_buffer.lines[b_line]

        remove_range(&last_line.characters, 0, b_char)
        inject_at(&last_line.characters, 0, ..first_line.characters[:a_char])

        remove_range(active_buffer.lines, a_line, b_line)
    }

    split := strings.split(string(text), "\n")

    defer delete(split)

    start_line := &active_buffer.lines[a_line]
    start_chars := start_line.characters[:]

    byte_offset := utf8.rune_offset(
        string(start_chars),
        int(a_char),
    )

    if byte_offset == -1 {
        byte_offset = len(start_chars)
    }

    if len(split) == 1 {
        first_paste_line := split[0]

        inject_at(&start_line.characters, byte_offset, ..transmute([]u8)first_paste_line)

        return
    }

    pre := active_buffer.lines[a_line].characters[:a_char]
    post := strings.clone(string(active_buffer.lines[a_line].characters[a_char:]))

    for i in 0..<len(split) {
        text_line := split[i]

        if i == 0 {
            buffer_line := &active_buffer.lines[a_line]

            inject_at(&buffer_line.characters, byte_offset, ..transmute([]u8)text_line)
            resize(&buffer_line.characters, byte_offset + len(text_line))

            continue
        }

        buffer_line_index := a_line + i

        new_buffer_line := BufferLine{}

        append(&new_buffer_line.characters, ..transmute([]u8)text_line)

        if i == (len(split) - 1) {
            append(&new_buffer_line.characters, ..transmute([]u8)post)
        }

        inject_at(active_buffer.lines, buffer_line_index, new_buffer_line)
    }

}

byte_to_pos :: proc(byte: u32) -> (line_index: int, byte_in_line: u32) {
    local_byte: u32 = 0
    for buf_line, i in active_buffer.lines {
        line_len := u32(len(buf_line.characters)) + 1

        if local_byte + line_len > byte {
            line_index = i
            byte_in_line = byte - local_byte
            break
        }

        local_byte += line_len
    }

    return line_index, byte_in_line
}


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
get_buffer_index :: proc(buffer: ^Buffer) -> int {
    for &local_buffer, index in buffers {
        if local_buffer == buffer {
            return index
        }
    }

    return -1
}

@(private="package")
find_search_hits :: proc() {
    clear(&search_hits)

    runes := utf8.string_to_runes(buffer_search_term)

    for line,i in active_buffer.lines {
        found, idx := contains_runes(string(line.characters[:]), runes)

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
) -> vec2 {
    pen := input_pen

    true_font_height := ascender - descender

    line_height := true_font_height

    if line_pos.y < 0 {
        pen.y = pen.y + line_height

        return pen
    }

    chars := string(buffer_line.characters[:])

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
                0,
                line_pos.y,
                fb_size.x,
                true_font_height,
            },
            no_texture,
            BG_MAIN_20,
            vec2{},
            2,
        )

        add_rect(&rect_cache,
            rect{
                0,
                line_pos.y + true_font_height - general_line_thickness_px,
                fb_size.x,
                general_line_thickness_px,
            },
            no_texture,
            BG_MAIN_30,
            vec2{},
            2.5,
        )

        add_rect(&rect_cache,
            rect{
                0,
                line_pos.y,
                fb_size.x,
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
            pen.y - active_buffer.scroll_y
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

    active_buffer^.offset_x = (max_line_size.x) + (buffer_font_size * .5)

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
                0 - active_buffer.scroll_y,
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

    active_buffer.first_drawn_line = -1
    active_buffer.last_drawn_line = -1

    for &buffer_line, index in buffer_lines {
        line_pos := vec2{
            pen.x - active_buffer.scroll_x + active_buffer.offset_x,
            pen.y - active_buffer.scroll_y,
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
        )
    }

    draw_autocomplete()
    
    draw_rects(&rect_cache)
    reset_rect_cache(&rect_cache)

    /*
        TEXT, especially code text (which has unknown varying background colours)
        must be drawn on a separate pass, otherwise blending is not possible.
        thanks opengl
    */
    draw_rects(&text_rect_cache)
    reset_rect_cache(&text_rect_cache)
}

draw_autocomplete :: proc() {
    error := ft.set_pixel_sizes(primary_font, 0, u32(buffer_font_size))
    assert(error == .Ok)

    ascender := f32(primary_font.size.metrics.ascender >> 6)
    descender := f32(primary_font.size.metrics.descender >> 6)

    if len(completion_hits) < 1 {
        return
    }

    padding := math.round_f32((buffer_font_size) * .25)

    y_pos := buffer_cursor_pos.y -
        active_buffer.scroll_y + ascender-descender + (padding * 2)

    pen := vec2{
        buffer_cursor_pos.x - active_buffer.scroll_x + active_buffer.offset_x,
        y_pos,
    }

    widest : f32 = 0

    end_idx := min(selected_completion_hit + 5, len(completion_hits))

    if selected_completion_hit >= len(completion_hits) {
        selected_completion_hit = 0
    }

    for i in selected_completion_hit..<end_idx {
        if i >= len(completion_hits) {
            break
        }

        hit := &completion_hits[i]

        size := add_text_measure(
            &text_rect_cache,
            pen,
            i == selected_completion_hit ? TEXT_MAIN : TEXT_DARKER,
            buffer_font_size,
            hit.label,
            10,
        )

        if size.x > widest do widest = size.x

        pen.y += ascender - descender
    }

    border_width := general_line_thickness_px

    base_rect := rect{
        pen.x - padding,
        y_pos - padding,
        widest + padding * 2,
        pen.y - y_pos + padding * 2,
    }

    add_rect(
        &rect_cache,
        base_rect,
        no_texture,
        BG_MAIN_10,
        vec2{},
        9,
    )

    add_rect(
        &rect_cache,
        rect{
            pen.x - padding - border_width,
            y_pos - padding - border_width,
            widest + padding * 2 + border_width * 2,
            pen.y - y_pos + padding * 2 + border_width * 2,
        },
        no_texture,
        BG_MAIN_30,
        vec2{},
        9,
    )

    first_hit := &completion_hits[selected_completion_hit]

    if first_hit == nil {
        return
    }

    if first_hit.detail == "" && first_hit.documentation == "" {
        return
    }

    start_pen := vec2{
        base_rect.x + base_rect.width + padding*2,
        base_rect.y + padding*2,
    }

    em := ui_smaller_font_size

    {
        pen := vec2{start_pen.x, start_pen.y}

        if first_hit.detail != "" {
            pen = add_text(
                &text_rect_cache,
                pen,
                TEXT_MAIN,
                ui_smaller_font_size,
                first_hit.detail,
                10,
                false,
                -1,
                true,
                true
            )
        }
        
        if first_hit.documentation != "" {
            pen = add_text(
                &text_rect_cache,
                pen,
                TEXT_MAIN,
                ui_smaller_font_size,
                first_hit.documentation,
                10,
                false,
                em * 20,
                true,
                true
            )
        }
        

        width := pen.x - start_pen.x
        height := (pen.y - start_pen.y)

        box := rect{
            start_pen.x - padding,
            start_pen.y - padding,
            width + padding * 2,
            height + padding * 2,
        }

        add_rect(
            &rect_cache,
            box,
            no_texture,
            BG_MAIN_10,
            vec2{},
            8,
        )

        add_rect(
            &rect_cache,
            rect{
                start_pen.x - border_width - padding,
                start_pen.y - padding - border_width,
                width + padding * 2 + border_width * 2,
                height + padding * 2 + border_width * 2,
            },
            no_texture,
            BG_MAIN_30,
            vec2{},
            8,
        )
    }
}

@(private="package")
open_file :: proc(file_name: string) {
    if active_buffer != nil {
        active_buffer^.cursor_char_index = buffer_cursor_char_index
        active_buffer^.cursor_line = buffer_cursor_line
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

        return
    }

    data, ok := os.read_entire_file_from_filename(file_name)
    defer delete(data)

    if !ok {
        fmt.println("failed to open file")

        return
    }

    data_string := string(data)
    
    lines := strings.split(data_string, "\n")
    defer delete(lines)

    buffer_lines := new([dynamic]BufferLine)

    new_buffer := new(Buffer)
    new_buffer^.lines = buffer_lines
    new_buffer^.file_name = file_name
    
    content := make([dynamic]u8, len(data))
    copy(content[:], data)
    
    new_buffer^.content = content

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
 
    when ODIN_DEBUG {
        fmt.println("Validating buffer lines")
    }
    
    for line in lines { 
        chars := make([dynamic]u8)
        
        append_elems(&chars, ..transmute([]u8)line)

        for r in line {
            get_char(buffer_font_size, u64(r))
        }

        append_elem(buffer_lines, BufferLine{
            characters=chars,
        })
    }

    active_buffer = new_buffer

    append(&buffers, new_buffer)
    
    set_buffer_cursor_pos(0,0)
    constrain_scroll_to_cursor() 

    thread.run(lsp_handle_file_open)

}

close_file :: proc(file_name: string) -> (ok: bool) {
    buffer_to_close : ^Buffer
    
    for buffer in buffers {
    
    }
    return true
}

save_buffer :: proc() {
    buffer_to_save := make([dynamic]u8)
    defer delete(buffer_to_save)

    for line, index in active_buffer.lines {
        if index != 0 {
            append(&buffer_to_save, '\n');
        }

        line_string := string(line.characters[:])
        for character in line_string {
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
    tab_string := utf8.runes_to_string(tab_chars)

    old_length := len(line.characters)
    old_byte_length := len(line.characters)
    
    inject_at(&line.characters, buffer_cursor_char_index, ..transmute([]u8)tab_string)
    
    buffer_cursor_accumulated_byte_position := compute_byte_offset(
        active_buffer, 
        buffer_cursor_line,
        buffer_cursor_char_index,
    )

    notify_server_of_change(
        active_buffer,

        buffer_cursor_accumulated_byte_position,
        buffer_cursor_accumulated_byte_position,

        buffer_cursor_line,
        buffer_cursor_char_index,

        buffer_cursor_line,
        buffer_cursor_char_index,

        transmute([]u8)tab_string,
    )    

    set_buffer_cursor_pos(
        buffer_cursor_line,
        buffer_cursor_char_index+tab_spaces,
    )
}

remove_char :: proc() {
    defer {
        get_autocomplete_hits(buffer_cursor_line, buffer_cursor_char_index, "1", "")
    }

    line := &active_buffer.lines[buffer_cursor_line] 
    line_string := string(line.characters[:])
    
    char_index := buffer_cursor_char_index 

    if char_index > len(line_string)  {
        char_index = len(line_string)
    }

    target := utf8.rune_offset(
        line_string, char_index - 1
    )

    if target < 0 {
        if buffer_cursor_line == 0 {
            return
        }

        prev_line := &active_buffer.lines[buffer_cursor_line - 1]
        prev_line_len := len(string(prev_line.characters[:]))

        // Buffer Manipulation
        {
            new_bytes := make([dynamic]u8) 

            append_elems(&new_bytes, ..prev_line.characters[:])
            append_elems(&new_bytes, ..line.characters[:])

            prev_line^.characters = new_bytes

            ordered_remove(active_buffer.lines, buffer_cursor_line)
        }

        buffer_cursor_accumulated_byte_position := compute_byte_offset(
            active_buffer, 
            buffer_cursor_line-1,
            prev_line_len,
        )

        notify_server_of_change(
            active_buffer,
            buffer_cursor_accumulated_byte_position,
            buffer_cursor_accumulated_byte_position + 1,
            buffer_cursor_line-1,
            prev_line_len,
            buffer_cursor_line,
            0,
            {},
        )
 
        set_buffer_cursor_pos(buffer_cursor_line-1, prev_line_len)
        
        return
    }

    current_indent := get_line_indent_level(buffer_cursor_line) 

    if target < current_indent * tab_spaces {
        for i in 0..<tab_spaces {
            ordered_remove(&line.characters, 0)
        }

        set_buffer_cursor_pos(
            buffer_cursor_line,
            char_index-tab_spaces,
        )

        buffer_cursor_accumulated_byte_position := compute_byte_offset(
            active_buffer, 
            buffer_cursor_line,
            buffer_cursor_char_index,
        )

        notify_server_of_change(
            active_buffer,

            buffer_cursor_accumulated_byte_position,
            buffer_cursor_accumulated_byte_position + tab_spaces,

            buffer_cursor_line,
            buffer_cursor_char_index,

            buffer_cursor_line,
            buffer_cursor_char_index + tab_spaces,

            {},
        )

        return
    }

    old_line_length := len(line_string)
    old_byte_length := len(line.characters)

    target_rune := utf8.rune_at_pos(line_string, char_index - 1)

    target_rune_size := utf8.rune_size(target_rune)
    
    remove_range(&line.characters, target, target + target_rune_size)

    buffer_cursor_accumulated_byte_position := compute_byte_offset(
        active_buffer, 
        buffer_cursor_line,
        buffer_cursor_char_index-1,
    )

    notify_server_of_change(
        active_buffer,

        buffer_cursor_accumulated_byte_position,
        buffer_cursor_accumulated_byte_position + target_rune_size,

        buffer_cursor_line,
        buffer_cursor_char_index-1,

        buffer_cursor_line,
        buffer_cursor_char_index,

        {},
    ) 

    set_buffer_cursor_pos(buffer_cursor_line, char_index - 1)
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

    length := len(string(prev_line.characters[:]))

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

    prev_line_last_char := string(prev_line.characters[index:index])

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

    if is_key_pressed(glfw.KEY_W) {
        key := key_store[glfw.KEY_W]

        if key.modifiers == CTRL {
            selected_completion_hit = clamp(
                selected_completion_hit - 1,
                0,
                len(completion_hits) - 1
            )

            attempt_resolve_request(selected_completion_hit)
        }
    } 

    if is_key_pressed(glfw.KEY_E) {
        key := key_store[glfw.KEY_E]

        if key.modifiers == CTRL {
            selected_completion_hit = clamp(
                selected_completion_hit + 1,
                0,
                len(completion_hits) - 1
            )

            attempt_resolve_request(selected_completion_hit)
        }
    }

    if is_key_pressed(glfw.KEY_LEFT_ALT) {
        insert_completion()
    }
    
    if is_key_pressed(glfw.KEY_ENTER) {
        defer {
            get_autocomplete_hits(buffer_cursor_line, buffer_cursor_char_index, "1", "")
        }

        index := clamp(buffer_cursor_char_index, 0, len(line.characters))
        
        after_cursor := line.characters[index:]
        before_cursor := line.characters[:index] 
        
        old_line_length := len(line.characters)
        old_byte_length := len(line.characters)
        
        resize(&line.characters, len(before_cursor))
        
        new_chars := make([dynamic]u8)
        append_elems(&new_chars, ..after_cursor)
        
        buffer_line := BufferLine{
            characters=new_chars,
        }
        
        new_line_num := buffer_cursor_line+1
        
        indent_level := determine_line_indent(new_line_num)
        
        bytes, _ := utf8.encode_rune(' ')
        size := utf8.rune_size(' ')
        
        for i in 0..<(indent_level) {
            inject_at(&buffer_line.characters, 0, ..bytes[:size])
        }
        
        inject_at(active_buffer.lines, new_line_num, buffer_line)

        cur_line_end_char := len(string(active_buffer.lines[buffer_cursor_line].characters[:]))
        cur_line_end_byte := compute_byte_offset(
            active_buffer,
            buffer_cursor_line,
            cur_line_end_char,
        ) 
 
        new_text := strings.concatenate({
            "\n",
            strings.repeat(" ", indent_level )
        })

        notify_server_of_change(
            active_buffer,

            cur_line_end_byte,
            cur_line_end_byte,

            buffer_cursor_line,
            cur_line_end_char,

            buffer_cursor_line,
            cur_line_end_char,

            transmute([]u8)new_text
        )
        
        set_buffer_cursor_pos(
            new_line_num,
            indent_level,
        )
        
        constrain_scroll_to_cursor()    

        return false
    }
    
    return false
}

@(private="package")
insert_into_buffer :: proc (key: rune) {
    line := &active_buffer.lines[buffer_cursor_line] 

    when ODIN_DEBUG {
        start := time.now()
    }

    buffer_cursor_byte_position := utf8.rune_offset(
        string(line.characters[:]), 
        buffer_cursor_char_index
    )

    if buffer_cursor_byte_position == -1 {
        buffer_cursor_byte_position = len(line.characters)
    }

    bytes, _ := utf8.encode_rune(key)
    size := utf8.rune_size(key)

    inject_at(&line.characters, buffer_cursor_byte_position, ..bytes[0:size])
    
    get_char(buffer_font_size, u64(key))
    add_missing_characters()

    constrain_scroll_to_cursor()

    when ODIN_DEBUG {
        now := time.now()

        fmt.println(time.diff(start,now), "to insert a character.")
    } 

    buffer_cursor_accumulated_byte_position := compute_byte_offset(
        active_buffer, 
        buffer_cursor_line,
        buffer_cursor_char_index,
    )
  
    notify_server_of_change(
        active_buffer,

        buffer_cursor_accumulated_byte_position,
        buffer_cursor_accumulated_byte_position,

        buffer_cursor_line,
        buffer_cursor_char_index,

        buffer_cursor_line,
        buffer_cursor_char_index,

        bytes[0:size]
    )

    set_buffer_cursor_pos(buffer_cursor_line, buffer_cursor_char_index+1)

    get_autocomplete_hits(buffer_cursor_line, buffer_cursor_char_index, "1", "")
}

@(private="package")
constrain_scroll_to_cursor :: proc() {
    amnt_above_offscreen := (buffer_cursor_target_pos.y - active_buffer.scroll_y) - cursor_edge_padding + cursor_height

    if amnt_above_offscreen < 0 {
        active_buffer.scroll_y -= -amnt_above_offscreen 
    }

    amnt_below_offscreen := (buffer_cursor_target_pos.y - active_buffer.scroll_y) - (fb_size.y - cursor_edge_padding)

    if amnt_below_offscreen >= 0 {
        active_buffer.scroll_y += amnt_below_offscreen 
    }

    amnt_left_offscreen := (buffer_cursor_target_pos.x - active_buffer.scroll_x)

    if amnt_left_offscreen < 0 {
        active_buffer.scroll_x -= -amnt_left_offscreen 
    }

    amnt_right_offscreen := (buffer_cursor_target_pos.x - active_buffer.scroll_x) - (fb_size.x - cursor_edge_padding)

    if amnt_right_offscreen >= 0 {
        active_buffer.scroll_x += amnt_right_offscreen 
    }
}

constrain_cursor_to_scroll :: proc() {
    if do_constrain_cursor_to_scroll == false {
        return
    }

    error := ft.set_pixel_sizes(primary_font, 0, u32(buffer_font_size))
    assert(error == .Ok)

    ascender  := f32(primary_font.size.metrics.ascender >> 6)
    descender := f32(primary_font.size.metrics.descender >> 6)
    line_height := ascender - descender

    top_visible_y := active_buffer.scroll_y + cursor_edge_padding
    bottom_visible_y := active_buffer.scroll_y + fb_size.y - cursor_edge_padding

    top_visible_line := int(top_visible_y / line_height)
    bottom_visible_line := int(bottom_visible_y / line_height) - 1

    cursor_line_index := int(buffer_cursor_target_pos.y / line_height)

    if cursor_line_index < top_visible_line {
        cursor_line_index = top_visible_line
    } else if cursor_line_index > bottom_visible_line {
        cursor_line_index = bottom_visible_line
    }

    set_buffer_cursor_pos(
        clamp(cursor_line_index, 0, len(active_buffer.lines)-1),
        buffer_cursor_char_index,
    )

    buffer_cursor_pos = buffer_cursor_target_pos
}

move_up :: proc() {
    if buffer_cursor_line > 0 {
        set_buffer_cursor_pos(
            buffer_cursor_line-1,
            buffer_cursor_char_index,
        )
    }

    constrain_scroll_to_cursor()
    clear(&completion_hits)
}

move_left :: proc() {
    buffer_cursor_desired_char_index = -1

    if buffer_cursor_char_index > 0 {
        line := active_buffer.lines[buffer_cursor_line]

        new := buffer_cursor_char_index - 1

        set_buffer_cursor_pos(
            buffer_cursor_line,
            new,
        )
    }

    constrain_scroll_to_cursor()
    clear(&completion_hits)
}

move_right :: proc() {
    buffer_cursor_desired_char_index = -1

    set_buffer_cursor_pos(
        buffer_cursor_line,
        buffer_cursor_char_index + 1,
    )

    constrain_scroll_to_cursor()
    clear(&completion_hits)
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
    clear(&completion_hits)
}

move_back_word :: proc() {
    defer clear(&completion_hits)
    current_line := active_buffer.lines[buffer_cursor_line]

    line_str := string(current_line.characters[:])

    byte_offset := utf8.rune_offset(line_str, buffer_cursor_char_index - 1)

    if byte_offset == -1 {
        return
    }

    current_rune := utf8.rune_at_pos(line_str, buffer_cursor_char_index - 1)

    chars_before_cursor := string(current_line.characters[:byte_offset])

    is_delimiter_sequence := is_delimiter_rune(current_rune)

    new_index := -1

    #reverse for char, rune_index in utf8.string_to_runes(chars_before_cursor) {
        is_delimiter := is_delimiter_rune(char)

        if is_delimiter {
            if is_delimiter_sequence == false {
                new_index = rune_index+1

                break
            }
        } else {
            if is_delimiter_sequence == true {
                new_index = rune_index+1

                break
            }
        }
    }

    if new_index == -1 {
        new_index = 0
    }

    set_buffer_cursor_pos(
        buffer_cursor_line,
        new_index,
    )

    constrain_scroll_to_cursor()
}

move_forward_word :: proc() {
    defer clear(&completion_hits)

    current_line := active_buffer.lines[buffer_cursor_line]

    line_str := string(current_line.characters[:])

    byte_offset := utf8.rune_offset(line_str, buffer_cursor_char_index)

    if byte_offset == -1 {
        return
    }

    current_rune := utf8.rune_at_pos(line_str, buffer_cursor_char_index)

    chars_after_cursor := string(current_line.characters[byte_offset:])

    is_delimiter_sequence := is_delimiter_rune(current_rune)

    rune_index := buffer_cursor_char_index
    for char in chars_after_cursor {
        is_delimiter := is_delimiter_rune(char)

        if is_delimiter {
            if is_delimiter_sequence == false {
                break
            }
        } else {
            if is_delimiter_sequence == true {
                break
            }
        }

        rune_index += 1
    } 

    set_buffer_cursor_pos(
        buffer_cursor_line,
        rune_index,
    )

    constrain_scroll_to_cursor()
}

scroll_down :: proc() {
    active_buffer.scroll_y += ((buffer_font_size * 1.2) * 80) * frame_time

    constrain_cursor_to_scroll()
}

scroll_up :: proc() {
    active_buffer.scroll_y -= ((buffer_font_size * 1.2) * 80) * frame_time

    constrain_cursor_to_scroll()
}

scroll_left :: proc() {
    active_buffer.scroll_x = max(
        active_buffer.scroll_x - ((buffer_font_size * 1.2) * 80) * frame_time,
        0
    )
}

scroll_right :: proc() {
    active_buffer.scroll_x += ((buffer_font_size * 1.2) * 80) * frame_time
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
    chars_string := utf8.runes_to_string(chars)
    defer delete(chars_string)

    start_byte := compute_byte_offset(active_buffer, start_line, 0)
    old_rune_count := utf8.rune_count(active_buffer.lines[end_line].characters[:])
        
    text := ""
    old_bytes := 0

    for i in start_line..=end_line {
        line := &active_buffer.lines[i]
        old_line_str := string(line.characters[:])
        old_bytes += len(old_line_str)
        
        inject_at(&line.characters, 0, ..transmute([]u8)chars_string[:])

        new_line_str := string(line.characters[:])
        
        text = strings.concatenate({text, new_line_str})
        if i < end_line {
            text = strings.concatenate({text, "\n"})
            old_bytes += 1
        }
    } 

    notify_server_of_change(
        active_buffer,
        start_byte,
        start_byte + old_bytes,
        start_line,
        0,
        end_line,
        old_rune_count,
        transmute([]u8)text,
    )
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

    start_byte := compute_byte_offset(active_buffer, start_line, 0)
    old_rune_count := utf8.rune_count(active_buffer.lines[end_line].characters[:])

    text := ""
    old_bytes := 0

    for i in start_line..=end_line {
        line := &active_buffer.lines[i]
        old_line_str := string(line.characters[:])
        old_bytes += len(old_line_str)

        count := 0
        for c in line.characters {
            if c == ' ' && count < 4 {
                count += 1
            } else {
                break
            }
        }

        if count > 0 {
            remove_range(&line.characters, 0, count)
        }

        new_line_str := string(line.characters[:])

        text = strings.concatenate({text, new_line_str})
        if i < end_line {
            text = strings.concatenate({text, "\n"})
            old_bytes += 1
        }
    }

    notify_server_of_change(
        active_buffer,
        start_byte,
        start_byte + old_bytes,
        start_line,
        0,
        end_line,
        old_rune_count,
        transmute([]u8)text,
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
get_buffer_by_name :: proc(file_name: string) -> ^Buffer {
    for &buffer in buffers {
        if buffer.file_name == file_name {
            return buffer
        }
    }

    return nil
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

    start_accumulated := compute_byte_offset(
        active_buffer, 
        a_line,
        a_char,
    )

    end_accumulated := compute_byte_offset(
        active_buffer, 
        b_line,
        b_char,
    )

    defer {
        notify_server_of_change(
            active_buffer,

            start_accumulated,
            end_accumulated,

            a_line,
            a_char,

            b_line,
            b_char,

            {},
        )
    }

    if a_line == b_line {
        target_line := &active_buffer.lines[a_line]
        remove_range(&target_line.characters, a_char, b_char)
    } else {
        first_line := &active_buffer.lines[a_line]
        last_line := &active_buffer.lines[b_line]

        remove_range(&last_line.characters, 0, b_char)
        inject_at(&last_line.characters, 0, ..first_line.characters[:a_char])

        remove_range(active_buffer.lines, a_line, b_line)
    }

    set_buffer_cursor_pos(a_line, a_char)
}

delete_line :: proc(line: int) {
    byte_offset := compute_byte_offset(active_buffer, line, 0)

    notify_server_of_change(
        active_buffer,
        byte_offset,
        byte_offset + len(active_buffer.lines[line].characters)+1,
        line,
        0,
        line+1,
        0,
        {},
    )

    ordered_remove(active_buffer.lines, line)
 
    if len(active_buffer.lines) == 0 {
        append(active_buffer.lines, BufferLine{})
    }

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

    defer {
        get_autocomplete_hits(
            buffer_cursor_line,
            buffer_cursor_char_index,
            "1", "",
        )
    }
        
    indent_spaces := determine_line_indent(buffer_cursor_line + 1)

    bytes, _ := utf8.encode_rune(' ')
    space_size := utf8.rune_size(' ')
    
    for i in 0..<indent_spaces {
        inject_at(&buffer_line.characters, 0, ..bytes[:space_size])
    }
   
    inject_at(active_buffer.lines, buffer_cursor_line + 1, buffer_line)

    new_text := strings.concatenate({
        "\n",
        strings.repeat(" ", indent_spaces)
    })

    cur_line_end_char := len(string(active_buffer.lines[buffer_cursor_line].characters[:]))
    cur_line_end_byte := compute_byte_offset(
        active_buffer,
        buffer_cursor_line,
        cur_line_end_char,
    ) 

    notify_server_of_change(
        active_buffer,

        cur_line_end_byte,
        cur_line_end_byte,

        buffer_cursor_line,
        cur_line_end_char,

        buffer_cursor_line,
        cur_line_end_char,

        transmute([]u8)new_text
    )

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
close_buffer :: proc(buf: ^Buffer) {
}

@(private="package")
paste_string :: proc(str: string, line: int, char: int) {
    split := strings.split(str, "\n")

    defer delete(split)

    absolute_byte_offset := compute_byte_offset(active_buffer, line, char)

    defer {
        notify_server_of_change(
            active_buffer,

            absolute_byte_offset,
            absolute_byte_offset,

            line,
            char,

            line,
            char,

            transmute([]u8)str,
        )

        line, line_byte := byte_to_pos(
            u32(absolute_byte_offset+len(str))
        )

        char := byte_offset_to_rune_index(
            string(active_buffer.lines[line].characters[:]),
            int(line_byte),
        )

        set_buffer_cursor_pos(line, char)
        
        constrain_scroll_to_cursor();
    }

    start_line := &active_buffer.lines[line]
    start_chars := start_line.characters[:]

    byte_offset := utf8.rune_offset(
        string(start_chars),
        char,
    )

    if byte_offset == -1 {
        byte_offset = len(start_chars)
    }

    if len(split) == 1 {
        first_paste_line := split[0]

        inject_at(&start_line.characters, byte_offset, ..transmute([]u8)first_paste_line)

        return
    }

    pre := active_buffer.lines[line].characters[:char]
    post := strings.clone(string(active_buffer.lines[line].characters[char:]))

    for i in 0..<len(split) {
        text_line := split[i]

        if i == 0 {
            buffer_line := &active_buffer.lines[line]

            inject_at(&buffer_line.characters, byte_offset, ..transmute([]u8)text_line)
            resize(&buffer_line.characters, byte_offset + len(text_line))

            continue
        }

        buffer_line_index := line + i

        new_buffer_line := BufferLine{}

        append(&new_buffer_line.characters, ..transmute([]u8)text_line)

        if i == (len(split) - 1) {
            append(&new_buffer_line.characters, ..transmute([]u8)post)
        }

        inject_at(active_buffer.lines, buffer_line_index, new_buffer_line)
    }
}


/*


INPUT


*/
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

    if is_key_pressed(glfw.KEY_PERIOD) {
        go_to_definition()
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

    if is_key_pressed(glfw.KEY_X) {
        undo_change()
    }

    if is_key_pressed(glfw.KEY_C) {
        redo_change()
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

        constrain_scroll_to_cursor()

        get_autocomplete_hits(
            buffer_cursor_line,
            buffer_cursor_char_index,
            "1",
            "",
        )

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
  
    if is_key_pressed(glfw.KEY_B) {
        key := key_store[glfw.KEY_B]
        
        if key.modifiers != CTRL {
            return false
        }
        
        buffer_search_term = ""

        selected_hit = nil

        clear(&search_hits)

        input_mode = .COMMAND

        cached_file := buffers[cached_buffer_index]
        open_file(cached_file.file_name)
        
        set_buffer_cursor_pos(
            cached_buffer_cursor_line,
            cached_buffer_cursor_char_index,
        )
        
        constrain_scroll_to_cursor()
        
        return false
    }
 
    return false
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

insert_completion :: proc() {
    if selected_completion_hit >= len(completion_hits) {
        return
    }

    completion := completion_hits[selected_completion_hit]

    insert_string := completion.label

    line := &active_buffer.lines[buffer_cursor_line]
    byte_offset := utf8.rune_offset(string(line.characters[:]), buffer_cursor_char_index)

    if byte_offset == -1 {
        byte_offset = len(line.characters)
    }

    filter_token_byte_size := len(completion_filter_token)
    completion_token_byte_size := len(completion.label)

    start_idx := byte_offset - filter_token_byte_size

    remove_range(&line.characters,
        start_idx, 
        start_idx + filter_token_byte_size
    )

    inject_at(
        &line.characters,
        start_idx,
        ..transmute([]u8)insert_string,
    )

    buffer_cursor_accumulated_byte_position := compute_byte_offset(
        active_buffer, 
        buffer_cursor_line,
        buffer_cursor_char_index,
    )
 
    notify_server_of_change(
        active_buffer,

        buffer_cursor_accumulated_byte_position - filter_token_byte_size,
        buffer_cursor_accumulated_byte_position,

        buffer_cursor_line,
        start_idx,

        buffer_cursor_line,
        buffer_cursor_char_index,

        transmute([]u8)insert_string
    )

    count := utf8.rune_count(insert_string)

    set_buffer_cursor_pos(
        buffer_cursor_line,
        buffer_cursor_char_index + count
    )

    get_autocomplete_hits(buffer_cursor_line, buffer_cursor_char_index, "1", "")
}

builder := strings.builder_make()

@(private="package")
escape_json :: proc(text: string) -> string {
    strings.builder_reset(&builder)

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

