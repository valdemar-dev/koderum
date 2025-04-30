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

prev_time : f64

@(private="package")
render :: proc() {
    gl.ClearColor(BG_MAIN_10.x, BG_MAIN_10.y, BG_MAIN_10.z, 1)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

    gl.UseProgram(shader_id)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.Uniform1i(first_texture_loc, 0)

    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    gl.Enable(gl.DEPTH_TEST)
    gl.DepthFunc(gl.LEQUAL)

    time := glfw.GetTime()

    frame_time = f32(time - prev_time)

    prev_time = time

    draw_buffer()
    draw_cursor()
    draw_ui()
    draw_buffer_info_view()
    draw_browser_view()

    glfw.SwapBuffers(window)
    glfw.PollEvents()
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

    z_pos := z_index / 256

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
) -> vec2 {
    pen := vec2{
        x=pos.x,
        y=pos.y,
    }

    line_height := font_height * 1.2

    for r,i in text {
        if r == '\t' {
            character := get_char(font_height, u64(' '))

            if character == nil {
                continue
            }

            advance_amount := (character.advance.x / 64) * f32(tab_spaces)
            pen.x += advance_amount

            continue
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
                pen.x + character.offset.x,
                (pen.y - character.offset.y + f32(ascend)),
                width,
                height,
            },
            rect{
                f32(uvs.x),
                f32(uvs.y),
                f32(uvs.w) - rect_pack_glyp_padding,
                f32(uvs.h) - rect_pack_glyp_padding,
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
    lang_string_chars: ^map[rune]StringVariant,
) -> (bool, StringVariant) {
    for char,count in encountered_string_chars {
        if count % 2 != 0 {
            assert(lang_string_chars != nil)

            return true,lang_string_chars[char]
        }
    }

    return false, .A
}

try_add_string_encounter :: proc(
    r: rune,
    lang_string_chars: ^map[rune]StringVariant
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

add_code_text :: proc(
    rect_cache: ^RectCache,
    pos: vec2,
    font_height: f32,
    text: string,
    z_index : f32,
    buffer_line: ^BufferLine,
) -> vec2 {
    pen := vec2{
        x=pos.x,
        y=pos.y,
    }

    highlight_height : f32

    if do_highlight_indents {
        error := ft.set_pixel_sizes(primary_font, 0, u32(buffer_font_size))
        if error != .Ok do return pen

        asc := primary_font.size.metrics.ascender >> 6
        desc := primary_font.size.metrics.descender >> 6

        highlight_height = f32(asc - desc)
    }

    line_height := font_height * 1.2

    is_start_of_line := true

    word_idx := 0
    words_len := len(buffer_line.words)

    word := words_len > 0 ? &buffer_line.words[word_idx] : nil

    set_word :: proc(word: ^^WordDef, word_idx: ^int, buffer_line: ^BufferLine, i: int) {
        if word^ == nil {
            return
        }

        if i32(i) < word^.end {
            return
        }

        word_idx^ += 1

        if word_idx^ >= len(buffer_line.words) - 1 {
            return
        }

        new_word := &buffer_line.words[word_idx^]

        if new_word != nil {
            word^ = new_word
        } 
    }
 
    error := ft.set_pixel_sizes(primary_font, 0, u32(font_height))
    assert(error == .Ok)

    ascend := primary_font.size.metrics.ascender >> 6

    lang_string_chars := string_char_language_list[active_buffer.ext]

    for r,i in text {
        set_word(&word, &word_idx, buffer_line, i) 

        if r != ' ' && is_start_of_line == true {
            is_start_of_line = false
        }

        if r == '\t' {
            character := get_char(font_height, u64(' '))

            if character == nil {
                continue
            }

            color := differentiate_tab_and_spaces ? BG_MAIN_30 : BG_MAIN_20

            if do_highlight_indents {
                add_rect(rect_cache,
                    rect{
                        pen.x,
                        pen.y,
                        3,
                        line_height,
                    },
                    no_texture,
                    color,
                )
            }

            advance_amount := (character.advance.x / 64) * f32(tab_spaces)
            pen.x += advance_amount

            continue
        } else if r == ' ' && do_highlight_indents && i % tab_spaces == 0 && is_start_of_line {
            character := get_char(font_height, u64(' '))

            if character == nil {
                continue
            }

            add_rect(rect_cache,
                rect{
                    pen.x,
                    pen.y,
                    3,
                    line_height,
                },
                no_texture,
                BG_MAIN_20,
            )

            pen.x += (character.advance.x / 64)

            continue
        }

        if pen.x > fb_size.x {
            break
        }

        character := get_char(font_height, u64(r))

        if character == nil {
            character = get_char(font_height, u64(0))

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

        is_in_string, variant := is_char_in_string(lang_string_chars)

        if is_in_string {
            color = string_variants[variant]
        } else if word != nil {
            hl_color := &highlight_colors[word.word_type]

            if hl_color != nil {
                color = hl_color^
            }
        }       

        add_rect(rect_cache,
            rect{
                pen.x + character.offset.x,
                (pen.y - character.offset.y + f32(ascend)),
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

        pen.x = pen.x + (character.advance.x / 64)
        pen.y = pen.y + character.advance.y
    }

    return pen
}
