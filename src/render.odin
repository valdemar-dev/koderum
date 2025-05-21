#+private
package main

import gl "vendor:OpenGL"
import "core:thread"
import "core:time"
import "core:fmt"
import "vendor:glfw"
import "core:math"
import "core:strings"
import ft "../../alt-odin-freetype"

@(private="package")
frame_time : f32

@(private="package")
rect_cache := RectCache{}

@(private="package")
text_rect_cache := RectCache{}

prev_time : f64

@(private="package")
render :: proc() {
    gl.ClearColor(1,0,0,1)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)

    gl.UseProgram(shader_id)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.Uniform1i(first_texture_loc, 0)

    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    gl.Enable(gl.DEPTH_TEST)
    gl.DepthFunc(gl.LESS)

    time := glfw.GetTime()
    frame_time = f32(time - prev_time)
    prev_time = time

    draw_cursor()
    draw_ui()

    draw_buffer()

    draw_buffer_info_view()
    draw_browser_view()

    when ODIN_DEBUG {
        draw_debug()
    }
}

indices_rawptr := rawptr(uintptr(0))
draw_rects :: proc(cache: ^RectCache, vao := vao, vbo := vbo) {
    gl.BindVertexArray(vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BufferData(gl.ARRAY_BUFFER, cache.vertices_size, cache.raw_vertices, gl.DYNAMIC_DRAW)

    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, cache.indices_size, cache.raw_indices, gl.DYNAMIC_DRAW)

    gl.BindVertexArray(vao)
    gl.DrawElements(gl.TRIANGLES, i32(len(cache.indices)), gl.UNSIGNED_INT, indices_rawptr)
    gl.BindVertexArray(0)
}

reset_rect_cache :: proc(cache: ^RectCache) {
    clear(&cache.indices)
    clear(&cache.vertices)

    cache^.indices_size = 0
    cache^.vertices_size = 0
    cache^.vertex_offset = 0
}

delete_rect_cache :: proc(cache: ^RectCache) {
    delete(cache.vertices)
    delete(cache.indices)
} 

normalize_to_texture_coords :: proc(texture_rect: rect, atlas_size: vec2) -> [4]vec2 {
    result : [4]vec2 = {}

    end_pos_x := (texture_rect.x + texture_rect.width)
    end_pos_y := (texture_rect.y + texture_rect.height) 

    result[0] = vec2{texture_rect.x / atlas_size.x, texture_rect.y / atlas_size.y}
    result[1] = vec2{end_pos_x / atlas_size.x, texture_rect.y / atlas_size.y}
    result[2] = vec2{end_pos_x / atlas_size.x, end_pos_y / atlas_size.y}
    result[3] = vec2{texture_rect.x / atlas_size.x, end_pos_y / atlas_size.y}

    return result
}

add_rect :: proc(cache: ^RectCache, input_rect: rect, texture: rect, color: vec4, atlas_size := vec2{512,512}, z_index : f32 = 0, invert_x : bool = false) {
    z_pos := z_index / 1000000

    rectangle := rect{
        input_rect.x,
        input_rect.y,
        input_rect.width,
        input_rect.height,
    }

    normalized_tex : [4]vec2 = {
        vec2{-1,-1},
        vec2{-1,-1},
        vec2{-1,-1},
        vec2{-1,-1},
    }

    if texture.width > 0 {
        normalized_tex = normalize_to_texture_coords(texture, atlas_size)
    }

    tr_pos := vec2{rectangle.x + rectangle.width, rectangle.y} 
    tr_tex := normalized_tex[1]

    br_pos := vec2{rectangle.x + rectangle.width, rectangle.y + rectangle.height}
    br_tex := normalized_tex[2]

    bl_pos := vec2{rectangle.x, rectangle.y + rectangle.height}
    bl_tex := normalized_tex[3]

    tl_pos := vec2{rectangle.x, rectangle.y}
    tl_tex := normalized_tex[0]

    if invert_x {
        tr_tex = normalized_tex[0]
        br_tex = normalized_tex[3]
        bl_tex = normalized_tex[2]
        tl_tex = normalized_tex[1]
    }

    append_elems(&cache.vertices,
        tr_pos.x, tr_pos.y, z_pos, tr_tex.x, tr_tex.y, color.x, color.y, color.z, color.w,
        br_pos.x, br_pos.y, z_pos, br_tex.x, br_tex.y, color.x, color.y, color.z, color.w,
        bl_pos.x, bl_pos.y, z_pos, bl_tex.x, bl_tex.y, color.x, color.y, color.z, color.w,
        tl_pos.x, tl_pos.y, z_pos, tl_tex.x, tl_tex.y, color.x, color.y, color.z, color.w,
    )

    append_elems(&cache.indices,
        cache.vertex_offset + 0, cache.vertex_offset + 1, cache.vertex_offset + 3,
        cache.vertex_offset + 1, cache.vertex_offset + 2, cache.vertex_offset + 3,
    )

    cache^.vertex_offset += 4

    cache^.vertices_size = len(cache.vertices) * size_of(cache.vertices[0])
    cache^.indices_size = len(cache.indices) * size_of(cache.indices[0])

    cache^.raw_vertices = raw_data(cache.vertices)
    cache^.raw_indices = raw_data(cache.indices)
}

measure_text :: proc (
    font_height: f32,
    text: string,
) -> vec2 {
    max_ascent : f32 = font_height

    highest := vec2{
        y=max_ascent,
    }

    pen := highest

    line_height := font_height * 1.2

    for r,i in text {
        if r == '\n' {
            pen.x = 0
            pen.y = pen.y + font_height * line_height

            continue
        }

        character := get_char(font_height, u64(r))

        if character == nil {
            continue
        }

        pen.x = pen.x + (character.advance.x / 64)
        pen.y = pen.y + character.advance.y

        if pen.x > highest.x {
            highest.x = pen.x
        }

        if pen.y > highest.y {
            highest.y = pen.y
        }
    }

    return pen
}


add_text_measure :: proc(
    rect_cache: ^RectCache,
    pos: vec2,
    tint : vec4,
    font_height: f32,
    text: string,
    z_index : f32 = 0,
    draw_missing_glyphs : bool = true,
) -> vec2 {
    pen := vec2{
        x=pos.x,
        y=pos.y,
    }

    pen = add_text(
        rect_cache,
        pen,
        tint,
        font_height,
        text,
        z_index,
    )

    return vec2{
        pen.x - pos.x,
        pen.y - pos.y,
    }
}

add_text :: proc(
    rect_cache: ^RectCache,
    pos: vec2,
    tint : vec4,
    font_height: f32,
    text: string,
    z_index : f32 = 0,
    draw_missing_glyphs : bool = false, 
    max_width: f32 = -1,
    do_wrap: bool = false,
    split_new_lines : bool = false,
) -> vec2 {
    pen := vec2{
        x=pos.x,
        y=pos.y,
    }

    line_height := font_height * 1.2

    for r,i in text {
        if split_new_lines == true && r == '\n' {
            pen.y += line_height
            pen.x = pos.x

            continue
        }

        if r == '\t' {
            character := get_char(font_height, u64(' '))

            if character == nil {
                continue
            }

            advance_amount := (character.advance.x / 64) * f32(tab_spaces)
            pen.x += advance_amount

            continue
        }

        if pen.x - pos.x > max_width && max_width > -1 {
            break
        }

        if pen.x > fb_size.x {
            break
        }

        character := get_char(font_height, u64(r))

        if character == nil {
            if draw_missing_glyphs == false {
                continue
            }

            character = get_char(font_height, u64(0))

            if character == nil {
                continue
            }
        }
        
        if font_height in char_uv_maps == false {
            continue
        }

        index := char_uv_maps[font_height]

        char_uv_map := char_uv_maps_array[index]

        uvs_index := char_uv_map[u64(r)]
        uvs := char_rects[uvs_index]
      
        height := f32(character.rows)
        width := f32(character.width)

        error := ft.set_pixel_sizes(primary_font, 0, u32(font_height))
        assert(error == .Ok)

        ascend := primary_font.size.metrics.ascender >> 6
       
        add_rect(rect_cache,
            rect{
                math.round_f32(pen.x + character.offset.x),
                math.round_f32((pen.y - character.offset.y + f32(ascend))),
                math.round_f32(width),
                math.round_f32(height),
            },
            rect{
                math.round_f32(f32(uvs.x)),
                math.round_f32(f32(uvs.y)),
                math.round_f32(f32(uvs.w) - rect_pack_glyp_padding),
                math.round_f32(f32(uvs.h) - rect_pack_glyp_padding),
            },
            tint,
            char_uv_map_size,
            z_index,
        )

        pen.x = pen.x + (character.advance.x / 64)
        pen.y = pen.y + character.advance.y
    }

    return pen
}

@(private="package")
encountered_string_chars : map[rune]int 

is_char_in_string :: proc(
    lang_string_chars: ^map[rune]vec4,
) -> (bool, vec4) {
    for char,count in encountered_string_chars {
        if count % 2 != 0 {
            assert(lang_string_chars != nil)

            return true,lang_string_chars[char]
        }
    }

    return false, vec4{},
}

try_add_string_encounter :: proc(
    r: rune,
    lang_string_chars: ^map[rune]vec4,
) {
    if lang_string_chars == nil {
        return
    }
    
    if r not_in lang_string_chars {
        return
    }

    existing_encounter := &encountered_string_chars[r]

    if existing_encounter != nil {
        encountered_string_chars[r] = existing_encounter^ + 1

        return
    }

    encountered_string_chars[r] = 1
}

set_word :: proc(
    word: ^^WordDef,
    word_idx: ^int,
    buffer_line: ^BufferLine,
    i: int,
) {
    pos := i32(i)
    ws  := buffer_line.words

    if word^ != nil {
        cur := word^
        if pos >= cur.start && pos < cur.end {
            return
        }
    }

    startIdx := 0

    if word^ != nil {
        startIdx = word_idx^ + 1
    }

    for idx := startIdx; idx < len(ws); idx += 1 {
        w := &ws[idx]

        if pos < w.start {
            break
        }

        if pos < w.end {
            word^     = w
            word_idx^ = idx
            return
        }
    }

    word^ = nil
}

process_highlights :: proc(i: int, is_hl_start,positive_dir,negative_dir,is_hl_end: bool, advance_amount: f32, highlight_width,highlight_offset: ^f32) -> (was_highlighted: bool) {
    if input_mode != .HIGHLIGHT {
        return false
    }        

    if (is_hl_end) && (is_hl_start) {
        positive_dir := buffer_cursor_char_index >= highlight_start_char

        if positive_dir {
            if i < highlight_start_char {
                highlight_offset^ += advance_amount

                return false
            } else if i >= buffer_cursor_char_index {
                return false
            }

            highlight_width^ += advance_amount

            return true
        } else {
            if i < buffer_cursor_char_index {
                highlight_offset^ += advance_amount

                return false
            } else if i >= highlight_start_char {
                return false
            }

            highlight_width^ += advance_amount

            return true
        }
    }

    if (is_hl_start) && (positive_dir) && (!is_hl_end) {
        if i < highlight_start_char {
            highlight_offset^ += advance_amount

            return false
        }

        highlight_width^ += advance_amount

        return true
    } else if (is_hl_end) && (positive_dir) && (!is_hl_start) {
        if i >= buffer_cursor_char_index {
            return false
        }

        highlight_width^  += advance_amount

        return true
    }

    if (is_hl_end) && (negative_dir) && (!is_hl_start) {
        if i < buffer_cursor_char_index {
            highlight_offset^ += advance_amount

            return false
        }

        highlight_width^ += advance_amount

        return true
    } else if (is_hl_start) && (negative_dir) && (!is_hl_end) {
        if i >= highlight_start_char {
            return false
        }

        highlight_width^ += advance_amount

        return true
    }
    
    return false
}


add_code_text :: proc(
    pos: vec2,
    font_height: f32,
    text: ^[]rune,
    z_index : f32,
    buffer_line: ^BufferLine,
    char_map: ^CharacterMap,
    ascender: f32,
    descender: f32,
    line_number: int,
) -> (offset: f32, width: f32) {
    pen := vec2{
        x=math.round_f32(pos.x),
        y=math.round_f32(pos.y),
    }

    highlight_height := ascender - descender

    line_height := font_height * 1.2

    is_start_of_line := true

    word_idx := 0
    words_len := len(buffer_line.words)

    word : ^WordDef

    lang_string_chars := string_char_language_list[active_buffer.ext]

    highlight_width : f32 = 0
    highlight_offset : f32 = 0

    is_hl_start := line_number == highlight_start_line
    is_hl_end := line_number == buffer_cursor_line

    positive_dir := buffer_cursor_line >= highlight_start_line
    negative_dir := buffer_cursor_line < highlight_start_line

    is_line_fully_highlighted : bool

    if (
        input_mode == .HIGHLIGHT &&
        line_number > buffer_cursor_line &&
        line_number < highlight_start_line
    ) {
        is_line_fully_highlighted = true
    } else if (
        input_mode == .HIGHLIGHT &&
        line_number < buffer_cursor_line &&
        line_number > highlight_start_line
    ) {
        is_line_fully_highlighted = true
    }

    is_hit_on_line := selected_hit != nil && selected_hit.line == line_number

    for r,i in text {
        set_word(&word, &word_idx, buffer_line, i) 

        if r != ' ' && is_start_of_line == true {
            is_start_of_line = false
        } 

        is_tab := (r == '\t')  
        is_space := (r == ' ' && is_start_of_line)

        if is_space || is_tab {
            character := get_char_with_char_map(char_map, font_height, u64(' '))

            if character == nil {
                continue
            }

            advance_amount : f32

            if is_space {
                advance_amount = (character.advance.x / 64)
            } else if is_tab {
                advance_amount = (character.advance.x / 64) * f32(tab_spaces)
            }

            was_highlighted := process_highlights(
                i,is_hl_start,positive_dir,
                negative_dir,is_hl_end,
                advance_amount,
                &highlight_width,&highlight_offset,
            )

            if was_highlighted || is_line_fully_highlighted {
                add_rect(&rect_cache,
                    rect{
                        pen.x + (advance_amount / 2) - 1,
                        pen.y + (highlight_height / 2) - 1,
                        2,
                        2,
                    },
                    no_texture,
                    text_highlight_color,
                    vec2{},
                    z_index,
                )
            } else if do_highlight_indents && i % tab_spaces == 0 {
                add_rect(&rect_cache,
                    rect{ pen.x, pen.y, general_line_thickness_px, highlight_height },
                    no_texture,
                    BG_MAIN_30,
                    vec2{},
                    z_index,
                )
            } 

            pen.x += advance_amount

            continue
        }

        character := get_char_with_char_map(char_map, font_height, u64(r))

        if character == nil {
            character = get_char_with_char_map(char_map, font_height, u64(0))

            if character == nil {
                continue
            }
        }
        
        if font_height in char_uv_maps == false {
            continue
        }

        try_add_string_encounter(r, lang_string_chars)

        index := char_uv_maps[font_height]
        char_uv_map := char_uv_maps_array[index]
        uvs_index := char_uv_map[u64(r)]
        uvs := char_rects[uvs_index]

        color := TEXT_MAIN

        advance_amount := (character.advance.x / 64)

        was_highlighted := process_highlights(
            i,is_hl_start,positive_dir,
            negative_dir,is_hl_end,
            advance_amount,
            &highlight_width,&highlight_offset,
        )

        is_in_string, variant := is_char_in_string(lang_string_chars)

        if is_hit_on_line && i >= selected_hit.start_char && i < selected_hit.end_char {
            color = RED
        } else if was_highlighted || is_line_fully_highlighted {
            color = text_highlight_color
        } else if is_in_string {
            color = variant
        } else if lang_string_chars != nil && r in lang_string_chars {
            color = lang_string_chars[r]
        } else if word != nil {
            color = word.color
        } else if r in special_chars {
            color = special_chars[r]
        }

        add_rect(&text_rect_cache,
            rect{
                pen.x + character.offset.x,
                pen.y - character.offset.y + ascender,
                f32(character.width),
                f32(character.rows),
            },
            rect{
                f32(uvs.x),
                f32(uvs.y),
                f32(uvs.w) - rect_pack_glyp_padding,
                f32(uvs.h) - rect_pack_glyp_padding,
            },
            color,
            char_uv_map_size,
            z_index,
        )

        pen.x = pen.x + advance_amount
        pen.y = pen.y + character.advance.y
    }

    if input_mode != .HIGHLIGHT {
        return 0,0
    }

    if buffer_cursor_line == line_number {
        return highlight_offset, highlight_width
    } else if line_number == highlight_start_line {
        return highlight_offset, highlight_width
    }

    if is_line_fully_highlighted {
        return 0,pen.x - pos.x
    }

    return 0,0
}
