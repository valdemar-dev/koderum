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
render :: proc() {
    gl.ClearColor(0, 0, 0, 0)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

    draw_temp()

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


add_rect :: proc(cache: ^RectCache, input_rect: rect, texture: rect, color: vec4, atlas_size := vec2{512,512}, z_pos : f32 = 0, invert_x : bool = false) {
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

add_text :: proc(
    rect_cache: ^RectCache,
    pos: vec2,
    tint : vec4,
    font_height: f32,
    text: string,
) -> vec2 {
    max_ascent : f32 = 0
    max_descent : f32 = 0

    for r in text {
        character := character_map[u64(r)]

        if character == nil {
            continue
        }

        if character.offset.y > max_ascent {
            max_ascent = character.offset.y
        }

        descent := f32(character.rows) - character.offset.y
        if descent > max_descent {
            max_descent = descent
        }
    }

    pen := vec2{
        x=pos.x,
        y=pos.y + max_ascent,
    }

    font_scale := font_height / font_size

    for r in text {
        if r == ' ' {
            sub := character_map[u64('a')]

            if sub == nil {
                report_missing_character(u64('a'))
                continue
            }

            pen.x += (sub.advance.x / 64) * font_scale

            continue
        }

        if r == '\n' {
            sub := character_map[u64('a')]

            if sub == nil {
                report_missing_character(u64('a'))
                continue
            }

            pen.x = pos.x
            pen.y = pen.y + line_height * font_scale

            continue
        }

        uvs := char_uv_map[u64(r)]
        character := character_map[u64(r)]

        if character == nil {
            report_missing_character(u64(r))

            continue
        }

        height := f32(character.rows) * font_scale
        width := f32(character.width) * font_scale

        add_rect(rect_cache,
            rect{
                pen.x + character.offset.x * font_scale,
                pen.y - character.offset.y * font_scale,
                width,
                height,
            },
            uvs,
            tint,
            char_uv_map_size,
        )

        pen.x = pen.x + (character.advance.x / 64) * font_scale
        pen.y = pen.y + character.advance.y * font_scale
    }

    return pen
}
