#+private
package main

import gl "vendor:OpenGL"
import "core:thread"
import "core:time"
import "core:fmt"
import "vendor:glfw"
import "core:math"
import "core:strings"
import "core:unicode/utf8"
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
    gl.ClearColor(BG_MAIN_10.x,BG_MAIN_10.y,BG_MAIN_10.z,1)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
    
    gl.UseProgram(shader_id)
    
    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    gl.Enable(gl.DEPTH_TEST)
    gl.DepthFunc(gl.LESS)
    
    
    time := glfw.GetTime()
    frame_time = f32(time - prev_time)
    prev_time = time

    draw_bg()
    
    draw_cursor()    
    draw_buffer()

    draw_notification()
    draw_alerts()

    draw_buffer_info_view()
    draw_browser_view()
    draw_grep_view()
    
    draw_yank_history()
    draw_find_and_replace()
    
    draw_ui()
    draw_terminal_emulator()

    when ODIN_DEBUG {
        draw_debug()
    }
    
}

draw_bg :: proc() {
    if len(background_image) == 0 do return
    
    gl.Uniform1i(first_texture_loc, 1)
    
    gl.Uniform1i(do_sample_rgb, 1)
    gl.ActiveTexture(gl.TEXTURE1)
    gl.BindTexture(gl.TEXTURE_2D, general_texture_id)
    
    box := rect{
        0, 0,
        fb_size.x,
        fb_size.y,
    }
    
    scale := max(box.width / background_image_size.x, box.height / background_image_size.y)
    new_size := vec2{ background_image_size.x * scale, background_image_size.y * scale }
    
    overflow := vec2{
        new_size.x - box.width,
        new_size.y - box.height,
    }
    
    uv_offset := vec2{
        overflow.x / 2 / scale,
        overflow.y / 2 / scale,
    }
    
    uvs := rect{
        x = uv_offset.x,
        y = uv_offset.y,
        width  = background_image_size.x - 2*uv_offset.x,
        height = background_image_size.y - 2*uv_offset.y
    }

    reset_rect_cache(&rect_cache)
    add_rect(&rect_cache, box, uvs, vec4{1,1,1,1}, background_image_size, 0)    
    draw_rects(&rect_cache)
    
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, font_texture_id)
    gl.Uniform1i(first_texture_loc, 0)
    gl.Uniform1i(do_sample_rgb, 0)
    
    reset_rect_cache(&rect_cache)
    add_rect(&rect_cache, box, no_texture, vec4{0,0,0,.8}, vec2{}, 1)
    draw_rects(&rect_cache)    
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

            advance_amount := (character.advance.x) * f32(tab_width)
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
    if is_not_highlighting() {
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
    ts_active := make([dynamic]^Token)
    defer delete(ts_active)
    ts_token_idx : int = 0
    
    lsp_tokens := buffer_line.lsp_tokens
    lsp_active := make([dynamic]^Token)
    defer delete(lsp_active)
    lsp_token_idx : int = 0
    
    highlight_width : f32 = 0
    highlight_offset : f32 = 0

    is_hl_start := line_number == highlight_start_line
    is_hl_end := line_number == buffer_cursor_line
    positive_dir := buffer_cursor_line >= highlight_start_line
    negative_dir := buffer_cursor_line < highlight_start_line

    is_line_fully_highlighted := false
    if is_not_highlighting() == false {
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

        current_pos := i32(rune_index)
        
        // Update ts_active
        for ts_token_idx < len(ts_tokens) && ts_tokens[ts_token_idx].char <= current_pos {
            append(&ts_active, &ts_tokens[ts_token_idx])
            ts_token_idx += 1
        }
        for len(ts_active) > 0 && ts_active[len(ts_active)-1].char + ts_active[len(ts_active)-1].length <= current_pos {
            _ = pop(&ts_active)
        }
        ts_current: ^Token = len(ts_active) > 0 ? ts_active[len(ts_active)-1] : nil
        
        // Update lsp_active
        for lsp_token_idx < len(lsp_tokens) && lsp_tokens[lsp_token_idx].char <= current_pos {
            append(&lsp_active, &lsp_tokens[lsp_token_idx])
            lsp_token_idx += 1
        }
        for len(lsp_active) > 0 && lsp_active[len(lsp_active)-1].char + lsp_active[len(lsp_active)-1].length <= current_pos {
            _ = pop(&lsp_active)
        }
        lsp_current: ^Token = len(lsp_active) > 0 ? lsp_active[len(lsp_active)-1] : nil        

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
                advance_amount = character.advance.x * f32(tab_width)
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
            } else if do_highlight_indents && rune_index % tab_width == 0 {
                add_rect(&rect_cache, rect{
                    pen.x, pen.y, font_base_px * line_thickness_em, highlight_height
                }, no_texture, BG_MAIN_30, vec2{}, z_index)
            }

            pen.x += advance_amount
            continue
        }

        character := get_char_with_char_map(char_map, font_height, u64(r))
        if character == nil {
            // this should be .notdef?
            character = get_char_with_char_map(char_map, font_height, 0)
            if character == nil {
                panic("no .notdef")
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
        } else if lsp_current != nil {
            color = lsp_current.color
        } else if ts_current != nil {
            color = ts_current.color
        } else if buffer.language_server != nil {
            color = buffer.language_server.language.filler_color
        } else if buffer.language_server == nil {
            color = TEXT_MAIN //ORANGE
        }

        if error != nil && (error.severity == 4) {
            color = vec4{color.x, color.y, color.z, 0.6}
        }

        add_rect(
            &text_rect_cache,
            rect{
                math.round_f32(pen.x + character.offset.x + 0.1),
                math.round_f32(pen.y - character.offset.y + ascender),
                math.round_f32(f32(character.width)),
                math.round_f32(f32(character.rows)),
            },
            rect{
                math.round_f32(f32(uvs.x)),
                math.round_f32(f32(uvs.y)),
                math.round_f32(f32(uvs.w) - rect_pack_glyp_padding),
                math.round_f32(f32(uvs.h) - rect_pack_glyp_padding),
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
                math.round_f32(pen.x + character.offset.x + 0.1),
                math.round_f32(pen.y - character.offset.y + ascender + f32(character.rows)),
                math.round_f32(f32(character.width)),
                math.round_f32(f32(character.rows))
            }, rect{
                math.round_f32(f32(uvs.x)), math.round_f32(f32(uvs.y)), math.round_f32(f32(uvs.w) - rect_pack_glyp_padding), math.round_f32(f32(uvs.h) - rect_pack_glyp_padding)
            }, color, char_uv_map_size, z_index - .1)
        }

        pen.x += math.round_f32(character.advance.x)
        pen.y += math.round_f32(character.advance.y)
    }

    if is_not_highlighting() {
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

/*

add_code_text :: proc(
    pos: vec2,
    font_height: f32,
    text: ^string,
    z_index: f32,
    buffer_line: ^BufferLine,
    char_map: ^CharacterMap,
    ascender: f32,
    descender: f32,
    line_number: int,
    buffer: ^Buffer,
) -> (offset: f32, width: f32) {
    pen := vec2{x = pos.x, y = pos.y}
    highlight_height := ascender - descender
    line_height := font_height * 1.2
    is_start_of_line := true

    errors := buffer_line.errors
    error: ^BufferError
    error_idx: int = 0

    ts_tokens := buffer_line.ts_tokens
    ts_active := make([dynamic]^Token)
    defer delete(ts_active)
    ts_token_idx: int = 0
    
    lsp_tokens := buffer_line.lsp_tokens
    lsp_active := make([dynamic]^Token)
    defer delete(lsp_active)
    lsp_token_idx: int = 0
    
    highlight_width: f32 = 0
    highlight_offset: f32 = 0

    is_hl_start := line_number == highlight_start_line
    is_hl_end := line_number == buffer_cursor_line
    positive_dir := buffer_cursor_line >= highlight_start_line
    negative_dir := buffer_cursor_line < highlight_start_line

    is_line_fully_highlighted := false
    if !is_not_highlighting() {
        if (line_number > buffer_cursor_line && line_number < highlight_start_line) ||
           (line_number < buffer_cursor_line && line_number > highlight_start_line) {
            is_line_fully_highlighted = true
        }
    }

    is_hit_on_line := selected_hit != nil && selected_hit.line == line_number
    rune_index: int = 0

    // Preprocess grapheme clusters
    clusters, _, _, _ := utf8.decode_grapheme_clusters(text^, track_graphemes = true)
    defer delete(clusters)

    for cluster, cluster_idx in clusters {
        // Extract cluster substring
        next_start := cluster_idx + 1 < len(clusters) ? clusters[cluster_idx + 1].byte_index : len(text^)
        cluster_str := (text^)[cluster.byte_index:next_start]
        cluster_rune_count := cluster.width
        cluster_advance: f32 = 0

        // Collect characters for the cluster
        cluster_characters: [dynamic]^Character
        defer delete(cluster_characters)
        for r, _ in cluster_str {
            character := get_char_with_char_map(char_map, font_height, u64(r))
            if character == nil {
                character = get_char_with_char_map(char_map, font_height, 0)
                if character == nil {
                    continue
                }
            }
            append(&cluster_characters, character)
            cluster_advance += character.advance.x
        }
        
        if len(cluster_characters) == 0 {
            continue
        }

        // Check if cluster is space or tab (single-rune clusters)
        cluster_is_tab := false
        cluster_is_space := false
        if cluster_rune_count == 1 {
            r, _ := utf8.decode_rune(cluster_str)
            cluster_is_tab = r == '\t'
            cluster_is_space = r == ' ' && is_start_of_line
        }
        if cluster_is_space || cluster_is_tab {
            character := cluster_characters[0]
            advance_amount: f32
            if cluster_is_space {
                advance_amount = character.advance.x
            } else {
                advance_amount = character.advance.x * f32(tab_width)
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
            } else if do_highlight_indents && rune_index % tab_width == 0 {
                add_rect(&rect_cache, rect{
                    pen.x, pen.y, font_base_px * line_thickness_em, highlight_height
                }, no_texture, BG_MAIN_30, vec2{}, z_index)
            }

            pen.x += advance_amount
            rune_index += 1
            first_r, _ := utf8.decode_rune(cluster_str)
            if first_r != ' ' && is_start_of_line {
                is_start_of_line = false
            }
            continue
        }

        // Non-space/tab cluster
        if pen.x + cluster_advance > fb_size.x {
            break
        }

        if pen.y < 0 {
            pen.x += cluster_advance
            rune_index += cluster_rune_count
            continue
        }

        // Process highlights for the entire cluster
        was_highlighted := process_highlights(
            rune_index,
            is_hl_start,
            positive_dir,
            negative_dir,
            is_hl_end,
            cluster_advance,
            &highlight_width,
            &highlight_offset,
        )

        // Determine if cluster intersects hit
        cluster_is_hit := is_hit_on_line && i32(rune_index) < i32(selected_hit.end_char) && i32(rune_index + cluster_rune_count) > i32(selected_hit.start_char)

        // Render each rune in the cluster
        color: vec4
        cluster_error: ^BufferError
        inner_idx := 0
        for r, _ in cluster_str {
            inner_idx += 1
            current_pos := rune_index

            // Update error
            if len(errors) > 0 {
                if error != nil && (error.char + error.width <= current_pos) {
                    error_idx += 1
                    if error_idx < len(errors) {
                        next_error := &errors[error_idx]
                        if next_error.char < current_pos {
                            error_idx += 1
                        }
                        if error_idx < len(errors) && current_pos >= errors[error_idx].char {
                            error = &errors[error_idx]
                        } else {
                            error = nil
                        }
                    } else {
                        error = nil
                    }
                } else if error == nil && error_idx < len(errors) {
                    if current_pos >= errors[error_idx].char {
                        error = &errors[error_idx]
                    }
                }
            }

            // Update ts_active
            for ts_token_idx < len(ts_tokens) && ts_tokens[ts_token_idx].char <= i32(current_pos) {
                append(&ts_active, &ts_tokens[ts_token_idx])
                ts_token_idx += 1
            }
            for len(ts_active) > 0 && ts_active[len(ts_active)-1].char + ts_active[len(ts_active)-1].length <= i32(current_pos) {
                _ = pop(&ts_active)
            }
            ts_current: ^Token = len(ts_active) > 0 ? ts_active[len(ts_active)-1] : nil

            // Update lsp_active
            for lsp_token_idx < len(lsp_tokens) && lsp_tokens[lsp_token_idx].char <= i32(current_pos) {
                append(&lsp_active, &lsp_tokens[lsp_token_idx])
                lsp_token_idx += 1
            }
            for len(lsp_active) > 0 && lsp_active[len(lsp_active)-1].char + lsp_active[len(lsp_active)-1].length <= i32(current_pos) {
                _ = pop(&lsp_active)
            }
            lsp_current: ^Token = len(lsp_active) > 0 ? lsp_active[len(lsp_active)-1] : nil

            if inner_idx == 1 {
                // Set color and error for the cluster using first rune
                color = TEXT_MAIN
                if cluster_is_hit {
                    color = TOKEN_COLOR_00
                } else if was_highlighted || is_line_fully_highlighted {
                    color = text_highlight_color
                } else if lsp_current != nil {
                    color = lsp_current.color
                } else if ts_current != nil {
                    color = ts_current.color
                } else if buffer.language_server != nil {
                    color = buffer.language_server.language.filler_color
                } else {
                    color = TEXT_MAIN
                }
                cluster_error = error
                if cluster_error != nil && cluster_error.severity == 4 {
                    color = vec4{color.x, color.y, color.z, 0.6}
                }
            }

            character := cluster_characters[inner_idx - 1]
            if font_height not_in char_uv_maps {
                rune_index += 1
                continue
            }

            index := char_uv_maps[font_height]
            char_uv_map := char_uv_maps_array[index]
            uvs_index := char_uv_map[u64(r)]
            uvs := char_rects[uvs_index]

            add_rect(
                &text_rect_cache,
                rect{
                    math.round_f32(pen.x + character.offset.x + 0.1),
                    math.round_f32(pen.y - character.offset.y + ascender),
                    math.round_f32(f32(character.width)),
                    math.round_f32(f32(character.rows)),
                },
                rect{
                    math.round_f32(f32(uvs.x)),
                    math.round_f32(f32(uvs.y)),
                    math.round_f32(f32(uvs.w) - rect_pack_glyp_padding),
                    math.round_f32(f32(uvs.h) - rect_pack_glyp_padding),
                },
                color,
                char_uv_map_size,
                z_index,
            )

            // Add underscore only for the first rune if error
            if inner_idx == 1 && cluster_error != nil && (cluster_error.severity == 1 || cluster_error.severity == 2) {
                underscore_char := get_char_with_char_map(char_map, font_height, u64('_'))
                if underscore_char == nil {
                    rune_index += 1
                    continue
                }
                uvs_index := char_uv_map[u64('_')]
                uvs := char_rects[uvs_index]
                error_color: vec4
                switch cluster_error.severity {
                case 1:
                    error_color = LSP_COLOR_ERROR
                case 2:
                    error_color = LSP_COLOR_WARN
                }
                add_rect(&text_rect_cache, rect{
                    math.round_f32(pen.x + underscore_char.offset.x + 0.1),
                    math.round_f32(pen.y - underscore_char.offset.y + ascender + f32(underscore_char.rows)),
                    math.round_f32(f32(underscore_char.width)),
                    math.round_f32(f32(underscore_char.rows))
                }, rect{
                    math.round_f32(f32(uvs.x)), math.round_f32(f32(uvs.y)), math.round_f32(f32(uvs.w) - rect_pack_glyp_padding), math.round_f32(f32(uvs.h) - rect_pack_glyp_padding)
                }, error_color, char_uv_map_size, z_index - .1)
            }

            pen.x += math.round_f32(character.advance.x)
            pen.y += math.round_f32(character.advance.y)
            rune_index += 1
        }

        // Update is_start_of_line based on first rune
        first_r, _ := utf8.decode_rune(cluster_str)
        if first_r != ' ' && is_start_of_line {
            is_start_of_line = false
        }
    }

    if is_not_highlighting() {
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

*/