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
    gl.ClearColor(0, 0, 0, 0)
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
) -> vec2 {
    pen := vec2{
        x=pos.x,
        y=pos.y,
    }

    for r,i in text {
        if r == '\n' {
            pen.x = pos.x
            pen.y = pen.y + font_height * line_height

            continue
        }

        character := get_char(font_height, u64(r))

        if character == nil {
            continue
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
