#+private file
package main

import "core:os"
import "core:fmt"
import "core:strings"
import gl "vendor:OpenGL"
import "vendor:glfw"
import "base:runtime"
import "core:unicode/utf8"
import "core:strconv"

BufferLine :: struct {
    characters: []rune,
}

@(private="package")
do_draw_line_count := true

Buffer :: struct {
    lines: ^[dynamic]BufferLine,
    x_offset: f32,

    x_pos: f32,
    y_pos: f32,

    file_name: string,
}

@(private="package")
buffers : map[string]^Buffer

@(private="package")
buffer_font_size : f32 = 16

@(private="package")
active_buffer : ^Buffer

@(private="package")
buffer_scroll_position : f32

@(private="package")
buffer_horizontal_scroll_position : f32

sb := strings.builder_make()

@(private="package")
draw_buffers :: proc() {

}

@(private="package")
draw_buffer :: proc() {
    if active_buffer == nil {
        return
    }

    buffer_lines := active_buffer.lines

    pen := vec2{0,0}

    line_height := buffer_font_size * 1.2

    strings.builder_reset(&sb)
    strings.write_int(&sb, len(buffer_lines))

    highest_line_string := strings.to_string(sb)

    max_line_size := measure_text(buffer_font_size, highest_line_string)

    active_buffer^.x_offset = (max_line_size.x) + (buffer_font_size * .5)

    if do_draw_line_count {
        add_rect(&rect_cache,
            rect{
                0,
                0 - buffer_scroll_position,
                max_line_size.x,
                f32(len(buffer_lines)) * (line_height),
            },
            no_texture,
            vec4{0.1,0,0,1},
        )
    }

    line_buffer := make([dynamic]byte, len(buffer_lines))
    defer delete(line_buffer)
    
    for buffer_line, index in buffer_lines {
        line_pos := vec2{
            pen.x - buffer_horizontal_scroll_position + active_buffer.x_offset,
            pen.y - buffer_scroll_position,
        }

        if line_pos.y > fb_size.y {
            break
        }

        if line_pos.y < 0 {
            pen.y = pen.y + line_height

            continue
        }

        chars := buffer_line.characters

        string := utf8.runes_to_string(chars[:])
        defer delete(string)

        if do_draw_line_count {
            line_pos := vec2{
                pen.x,
                pen.y - buffer_scroll_position
            }

            line_string := strconv.itoa(line_buffer[:], index+1)

            add_text(&rect_cache,
                line_pos,
                vec4{1,1,1,1},
                buffer_font_size,
                line_string
            )

        }

        add_text(
            &rect_cache,
            line_pos,
            vec4{1,1,1,1},
            buffer_font_size,
            string,
        )

        pen.y = pen.y + line_height
    }

    draw_rects(&rect_cache)

    reset_rect_cache(&rect_cache)
}

@(private="package")
open_file :: proc(file_name: string) {
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

        append_elem(buffer_lines, buffer_line)
    }

    buffers[file_name] = new_buffer

    active_buffer = new_buffer

    when ODIN_DEBUG {
        fmt.println("Updating fonts for buffer")
    }

    update_fonts()

    set_buffer_cursor_pos(0,0)
}

remove_char_at_index :: proc(runes: []rune, index: int) -> []rune {
    if index < 0 || index >= len(runes) {
        return runes
    }


    new_runes := make([dynamic]rune, 0, len(runes) - 1)

    append_elems(&new_runes, ..runes[0:index])
    append_elems(&new_runes, ..runes[index+1:])

    return new_runes[:]
}

insert_char_at_index :: proc(runes: []rune, index: int, c: rune) -> []rune {
    clamped_index := clamp(index, 0, len(runes))

    new_runes := make([dynamic]rune, 0, len(runes) + 1)
    
    append_elems(&new_runes, ..runes[0:clamped_index])
    append_elem(&new_runes, c)
    append_elems(&new_runes, ..runes[clamped_index:])

    return new_runes[:]
}

insert_chars_at_index :: proc(runes: []rune, index: int, chars: []rune) -> []rune {
    clamped_index := clamp(index, 0, len(runes))

    new_runes := make([dynamic]rune, 0, len(runes) + 1)
    
    append_elems(&new_runes, ..runes[0:clamped_index])
    append_elems(&new_runes, ..chars[:])
    append_elems(&new_runes, ..runes[clamped_index:])

    return new_runes[:]
}

close_file :: proc(file_name: string) -> (ok: bool) {
    if file_name in buffers == false {
        return false
    }

    file := buffers[file_name]

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

    fmt.println(buffer_to_save)
}

insert_tab_as_spaces:: proc() {
    line := &active_buffer.lines[buffer_cursor_line]

    tab_spaces := 4

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

        ordered_remove(active_buffer.lines, buffer_cursor_line)
        set_buffer_cursor_pos(buffer_cursor_line-1, prev_line_len)

        return
    }

    line^.characters = remove_char_at_index(line.characters, target)

    set_buffer_cursor_pos(buffer_cursor_line, target)
}

@(private="package")
handle_text_input :: proc() {
    if is_key_pressed(glfw.KEY_ESCAPE) {
        input_mode = .COMMAND
    }

    if is_key_pressed(glfw.KEY_TAB) {
        insert_tab_as_spaces()

        return
    }

    if active_buffer == nil {
        return
    }

    line := &active_buffer.lines[buffer_cursor_line] 
    
    char_index := buffer_cursor_char_index

    if is_key_pressed(glfw.KEY_BACKSPACE) {
        remove_char()

        return
    } 

    if is_key_pressed(glfw.KEY_ENTER) {
        index := clamp(buffer_cursor_char_index, 0, len(line.characters))

        after_cursor := line.characters[index:]
        before_cursor := line.characters[:index] 

        line^.characters = before_cursor

        buffer_line := BufferLine{
            characters=after_cursor,
        }

        inject_at(active_buffer.lines, buffer_cursor_line+1, buffer_line)
        set_buffer_cursor_pos(buffer_cursor_line+1, 0)
    }
}

@(private="package")
insert_into_buffer :: proc (key: rune) {
    line := &active_buffer.lines[buffer_cursor_line] 
    
    line^.characters = insert_char_at_index(line.characters, buffer_cursor_char_index, key)

    get_char(buffer_font_size, u64(key))
    add_missing_characters()

    set_buffer_cursor_pos(buffer_cursor_line, buffer_cursor_char_index+1)

    constrain_scroll_to_cursor()
}

constrain_scroll_to_cursor :: proc() {
    amnt_above_offscreen := (buffer_cursor_target_pos.y - buffer_scroll_position)

    if amnt_above_offscreen < 0 {
        buffer_scroll_position -= -amnt_above_offscreen 
    }

    amnt_below_offscreen := (buffer_cursor_target_pos.y - buffer_scroll_position) - (fb_size.y - 100)

    if amnt_below_offscreen >= 0 {
        buffer_scroll_position += amnt_below_offscreen 
    }

    amnt_left_offscreen := (buffer_cursor_target_pos.x - buffer_horizontal_scroll_position)

    if amnt_left_offscreen < 0 {
        buffer_horizontal_scroll_position -= -amnt_left_offscreen 
    }

    amnt_right_offscreen := (buffer_cursor_target_pos.x - buffer_horizontal_scroll_position) - (fb_size.x - 100)

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

    words_before_cursor := line.characters[:buffer_cursor_char_index]
    
    new_char_index : int

    #reverse for r,index in words_before_cursor {
        if r == ' ' {
            new_char_index = index

            break
        }
    }

    set_buffer_cursor_pos(
        buffer_cursor_line,
        new_char_index,
    )
}

move_forward_word :: proc() {
    line := active_buffer.lines[buffer_cursor_line]

    chars_after_cursor := line.characters[buffer_cursor_char_index:]
    
    new_char_index := buffer_cursor_char_index

    prev_was_space := false
    for r,index in chars_after_cursor {
        if r == ' ' {
            prev_was_space = true

            continue
        }

        if prev_was_space {
            new_char_index = index + buffer_cursor_char_index
            break
        }
    }

    set_buffer_cursor_pos(
        buffer_cursor_line,
        new_char_index,
    )
}

scroll_down :: proc() {
    buffer_scroll_position += ((buffer_font_size * line_height) * 20) * frame_time
}

scroll_up :: proc() {
    buffer_scroll_position -= ((buffer_font_size * line_height) * 20) * frame_time
}

@(private="package")
handle_buffer_input :: proc() {
    if is_key_pressed(glfw.KEY_S) {
        key := key_store[glfw.KEY_S]

        if key.modifiers == 2 {
            save_buffer()
        }

        return
    }

    if is_key_pressed(glfw.KEY_I) {
        input_mode = .TEXT

        return
    }

    if is_key_down(glfw.KEY_J) {
        key := key_store[glfw.KEY_J]

        if key.modifiers == 1 {
            scroll_down()

            return
        }
    }

    if is_key_pressed(glfw.KEY_J) {
        move_down()

        return
    }

    if is_key_down(glfw.KEY_K) {
        key := key_store[glfw.KEY_K]

        if key.modifiers == 1 {
            scroll_up()

            return
        }
    }

    if is_key_pressed(glfw.KEY_K) {
        move_up()

        return
    }

    if is_key_pressed(glfw.KEY_D) {
        move_left()

        return
    }

    if is_key_pressed(glfw.KEY_F) {
        move_right()

        return
    }

    if is_key_pressed(glfw.KEY_R) {
        move_back_word()

        return
    }

    if is_key_pressed(glfw.KEY_U) {
        move_forward_word()

        return
    }
}
