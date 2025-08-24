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
    gl.ClearColor(0,0,0,1)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
    
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
    draw_buffer()

    draw_notification()
    draw_alerts()

    draw_buffer_info_view()
    draw_browser_view()
    draw_grep_view()
    
    draw_yank_history()
    
    draw_ui()
    draw_terminal_emulator()

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
    max_width : f32 = -1,
) -> vec2 {
    error := ft.set_pixel_sizes(primary_font, 0, u32(font_height))
    assert(error == .Ok)

    ascend := primary_font.size.metrics.ascender >> 6
    descend := primary_font.size.metrics.descender >> 6

    max_ascent := f32(ascend - descend)

    highest := vec2{
        y=max_ascent,
    }

    pen := highest

    line_height := font_height * 1.2

    for r,i in text {
        if r == '\n' {
            pen.x = 0

            highest.y += line_height

            continue
        }

        character := get_char(font_height, u64(r))

        if character == nil {
            continue
        }

        pen.x = pen.x + (character.advance.x)

        if pen.x > highest.x {
            highest.x = pen.x
        }

        if math.round_f32(pen.x) > max_width && max_width > -1 {
            highest.y += line_height
            pen.x = 0
        }
    }

    return highest
}


add_text_measure :: proc(
    rect_cache: ^RectCache,
    pos: vec2,
    tint : vec4,
    font_height: f32,
    text: string,
    z_index : f32 = 0,
    draw_missing_glyphs : bool = true,
    max_width: f32 = -1,
    do_wrap: bool = false,
    split_new_lines : bool = false,
) -> vec2 {
    pen := vec2{
        x=pos.x,
        y=pos.y,
    }

    error := ft.set_pixel_sizes(primary_font, 0, u32(font_height))
    assert(error == .Ok)

    ascend := primary_font.size.metrics.ascender >> 6
    descend := primary_font.size.metrics.descender >> 6

    max_ascent := f32(ascend - descend)

    pen = add_text(
        rect_cache,
        pen,
        tint,
        font_height,
        text,
        z_index,
        draw_missing_glyphs,
        max_width,
        do_wrap,
        split_new_lines,
    )
    
    pen.y += max_ascent

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
    max_height: f32 = -1
) -> vec2 {
    pen := vec2{
        x=pos.x,
        y=pos.y,
    }

    error := ft.set_pixel_sizes(primary_font, 0, u32(font_height))
    assert(error == .Ok)

    ascend := primary_font.size.metrics.ascender >> 6
    descend := primary_font.size.metrics.descender >> 6

    line_height := f32(ascend - descend)

    highest_x : f32
       
    for r,i in text {
        defer if pen.x > highest_x {
            highest_x = pen.x
        }

        if split_new_lines == true && r == '\n' {
            pen.y += line_height
            pen.x = pos.x
            
            if (pen.y - pos.y) >= max_height && max_height != -1 {
                break
            }

            continue
        }

        if r == '\t' {
            character := get_char(font_height, u64(' '))

            if character == nil {
                continue
            }

            advance_amount := (character.advance.x) * f32(tab_spaces)
            pen.x += advance_amount

            continue
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

        if math.round_f32(pen.x - pos.x + width) > max_width && max_width > -1 {
            if do_wrap {
                pen.y += line_height
                pen.x = pos.x
                
                if (pen.y - pos.y + height) >= max_height && max_height != -1 {
                    break
                }
            } else {
                // dont touch this please
                continue
            }
        }
        
        if ((pen.y - pos.y) + height) >= max_height && max_height != -1 {
            break
        }

        add_rect(rect_cache,
            rect{
                (pen.x + character.offset.x) + 0.1,
                ((pen.y - character.offset.y + f32(ascend))) + 0.1,
                (width),
                (height),
            },
            rect{
                (f32(uvs.x)),
                (f32(uvs.y)),
                (f32(uvs.w) - rect_pack_glyp_padding),
                (f32(uvs.h) - rect_pack_glyp_padding),
            },
            tint,
            char_uv_map_size,
            z_index,
        )

        pen.x = pen.x + character.advance.x
        pen.y = pen.y + character.advance.y
    }

    if do_wrap {
        pen.y += line_height
        pen.x = highest_x
    }

    return pen
}

process_highlights :: proc(
    i: int, 
    is_hl_start,positive_dir,negative_dir,is_hl_end: bool, 
    advance_amount: f32, 
    highlight_width,highlight_offset: ^f32
) -> (was_highlighted: bool) {
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
    text: ^string,
    z_index : f32,
    buffer_line: ^BufferLine,
    char_map: ^CharacterMap,
    ascender: f32,
    descender: f32,
    line_number: int,
    buffer: ^Buffer,
) -> (offset: f32, width: f32) {
    pen := vec2{ x = pos.x, y = pos.y }
    highlight_height := ascender - descender
    line_height := font_height * 1.2
    is_start_of_line := true

    errors := buffer_line.errors
    error : ^BufferError
    error_idx : int = 0

    ts_tokens := buffer_line.ts_tokens
    ts_token : ^Token
    ts_token_idx : int = 0
    
    lsp_tokens := buffer_line.lsp_tokens
    lsp_token : ^Token
    lsp_token_idx : int = 0
    
    highlight_width : f32 = 0
    highlight_offset : f32 = 0

    if len(ts_tokens) > 0 && ts_tokens[0].char == 0 {
        ts_token = &ts_tokens[0]
    }
    
    if len(lsp_tokens) > 0 && lsp_tokens[0].char == 0 {
        lsp_token = &lsp_tokens[0]
    }

    is_hl_start := line_number == highlight_start_line
    is_hl_end := line_number == buffer_cursor_line
    positive_dir := buffer_cursor_line >= highlight_start_line
    negative_dir := buffer_cursor_line < highlight_start_line

    is_line_fully_highlighted := false
    if input_mode == .HIGHLIGHT {
        if (line_number > buffer_cursor_line && line_number < highlight_start_line) ||
           (line_number < buffer_cursor_line && line_number > highlight_start_line) {
            is_line_fully_highlighted = true
        }
    }

    is_hit_on_line := selected_hit != nil && selected_hit.line == line_number
    rune_index := 0
    for r, byte_index in text {
        defer rune_index += 1
        
        if len(errors) > 0 {
            if error != nil && (error.char + error.width <= rune_index) {
                error_idx += 1
                if error_idx < len(errors) {
                    next_error := &errors[error_idx]

                    if next_error.char < rune_index {
                        error_idx += 1
                    }

                    if error_idx < len(errors) && rune_index >= errors[error_idx].char {
                        error = &errors[error_idx]
                    } else {
                        error = nil
                    }
                } else {
                    error = nil
                }
            } else if error == nil && error_idx < len(errors) {
                if rune_index >= errors[error_idx].char {
                    error = &errors[error_idx]
                }
            }
        }

        defer if len(ts_tokens) > 0 {
            if ts_token != nil && (ts_token.char + ts_token.length <= i32(byte_index + 1)) {
                ts_token_idx += 1
                if ts_token_idx < len(ts_tokens) {
                    next_ts_token := &ts_tokens[ts_token_idx]

                    if next_ts_token.char < i32(byte_index) {
                        ts_token_idx += 1
                    }

                    if i32(byte_index + 1) >= next_ts_token.char {
                        ts_token = next_ts_token
                    } else {
                        ts_token = nil
                    }
                } else {
                    ts_token = nil
                }
            } else if ts_token == nil && ts_token_idx < len(ts_tokens) {
                next_ts_token := &ts_tokens[ts_token_idx]

                if i32(byte_index + 1) >= next_ts_token.char {
                    ts_token = next_ts_token
                }
            }
        }        
        
        defer if len(lsp_tokens) > 0 {
            if lsp_token != nil && (lsp_token.char + lsp_token.length <= i32(byte_index + 1)) {
                lsp_token_idx += 1
                if lsp_token_idx < len(lsp_tokens) {
                    next_lsp_token := &lsp_tokens[lsp_token_idx]

                    if next_lsp_token.char < i32(byte_index) {
                        lsp_token_idx += 1
                    }

                    if i32(byte_index + 1) >= next_lsp_token.char {
                        lsp_token = next_lsp_token
                    } else {
                        lsp_token = nil
                    }
                } else {
                    lsp_token = nil
                }
            } else if lsp_token == nil && lsp_token_idx < len(lsp_tokens) {
                next_lsp_token := &lsp_tokens[lsp_token_idx]

                if i32(byte_index + 1) >= next_lsp_token.char {
                    lsp_token = next_lsp_token
                }
            }
        }        

        if r != ' ' && is_start_of_line {
            is_start_of_line = false
        }

        is_tab := r == '\t'
        is_space := r == ' ' && is_start_of_line

        if is_space || is_tab {
            character := get_char_with_char_map(char_map, font_height, u64(' '))
            if character == nil {
                continue
            }

            advance_amount: f32
            if is_space {
                advance_amount = character.advance.x
            } else {
                advance_amount = character.advance.x * f32(tab_spaces)
            }

            was_highlighted := process_highlights(
                rune_index, 
                is_hl_start, 
                positive_dir, 
                negative_dir, 
                is_hl_end, 
                advance_amount, 
                &highlight_width, 
                &highlight_offset,
            )

            if was_highlighted || is_line_fully_highlighted {
                add_rect(&rect_cache, rect{
                    pen.x + (advance_amount / 2) - 1,
                    pen.y + (highlight_height / 2) - 1,
                    2, 2
                }, no_texture, text_highlight_color, vec2{}, z_index)
            } else if do_highlight_indents && rune_index % tab_spaces == 0 {
                add_rect(&rect_cache, rect{
                    pen.x, pen.y, font_base_px * line_thickness_em, highlight_height
                }, no_texture, BG_MAIN_30, vec2{}, z_index)
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
        
        if pen.x + character.advance.x > fb_size.x {
            break
        }
        
        if pen.y < 0 {
            pen.x += character.advance.x
            pen.y += character.advance.y
        
            continue
        }

        index := char_uv_maps[font_height]
        char_uv_map := char_uv_maps_array[index]
        uvs_index := char_uv_map[u64(r)]
        uvs := char_rects[uvs_index]

        advance_amount := character.advance.x
        was_highlighted := process_highlights(
            rune_index, 
            is_hl_start, 
            positive_dir, 
            negative_dir, 
            is_hl_end, 
            advance_amount, 
            &highlight_width, 
            &highlight_offset,
        )

        color := TEXT_MAIN

        if is_hit_on_line && rune_index >= selected_hit.start_char && rune_index < selected_hit.end_char {
            color = TOKEN_COLOR_00
        } else if was_highlighted || is_line_fully_highlighted {
            color = text_highlight_color
        } else if lsp_token != nil {
            color = lsp_token.color
        } else if ts_token != nil {
            color = ts_token.color
        } else if active_language_server != nil {
            color = active_language_server.language.filler_color
        } else if active_language_server == nil {
            color = TEXT_MAIN //ORANGE
        }

        if error != nil && (error.severity == 4) {
            color = vec4{color.x, color.y, color.z, 0.6}
        }

        add_rect(
            &text_rect_cache,
            rect{
                pen.x + character.offset.x + 0.1,
                pen.y - character.offset.y + ascender,
                f32(character.width), f32(character.rows)
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

        if error != nil && (error.severity == 1 || error.severity == 2) {
            character := get_char_with_char_map(char_map, font_height, u64('_'))

            if character == nil {
                continue
            }

            if font_height in char_uv_maps == false {
                continue
            }

            index := char_uv_maps[font_height]
            char_uv_map := char_uv_maps_array[index]
            uvs_index := char_uv_map[u64('_')]
            uvs := char_rects[uvs_index]

            color : vec4

            switch error.severity {
            case 1:
                color = LSP_COLOR_ERROR
            case 2:
                color = LSP_COLOR_WARN
            }

            add_rect(&text_rect_cache, rect{
                pen.x + character.offset.x + 0.1,
                pen.y - character.offset.y + ascender + f32(character.rows),
                f32(character.width), f32(character.rows)
            }, rect{
                f32(uvs.x), f32(uvs.y), f32(uvs.w) - rect_pack_glyp_padding, f32(uvs.h) - rect_pack_glyp_padding
            }, color, char_uv_map_size, z_index - .1)
        }

        pen.x += character.advance.x
        pen.y += character.advance.y
    }

    if input_mode != .HIGHLIGHT {
        return 0, 0
    }

    if buffer_cursor_line == line_number || line_number == highlight_start_line {
        return highlight_offset, highlight_width
    }

    if is_line_fully_highlighted {
        return 0, pen.x - pos.x
    }

    return 0, 0
}

TokenRange :: struct {
    start_char: i32,
    end_char: i32,
    color: vec4,
}

