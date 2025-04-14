#+private file
package main

import ft "../../alt-odin-freetype"
import "core:fmt"
import "core:mem"
import gl "vendor:OpenGL"
import "core:math"

import rp "vendor:stb/rect_pack"
import image "vendor:stb/image"

import "core:c"

@(private="package")
font_size : f32 = 16

@(private="package")
line_height := font_size * 1.2

@(private="package")
library : ft.Library

@(private="package")
faces : [dynamic]ft.Face = {}

@(private="package")
font_texture_id : u32

known_non_existing_chars : map[u64]bool

missing_characters : [dynamic]u64

load_font :: proc(path: cstring) -> ft.Face {
    face : ft.Face
    
    error : ft.Error

    error = ft.init_free_type(&library)
    if error != .Ok do return nil

    error = ft.new_face(library, path, 0, &face)
    if error != .Ok do return nil
    /*

    error = ft.set_char_size(face, 0, 16*64, 300, 300)
    if error != .Ok do return nil


    */
    error = ft.set_pixel_sizes(face, 0, u32(font_size))
    if error != .Ok do return nil

    return face
}

load_all_fonts :: proc() {
    // lower index higher importance
    font_list : []cstring = {
        "/usr/share/fonts/CascadiaMono/CaskaydiaMonoNerdFontMono-Regular.ttf"
    }

    for font in font_list {
        face := load_font(font)

        append_elem(&faces, face)
    }
}

@(private="package")
add_missing_characters :: proc() {
    if len(missing_characters) < 1 {
        return
    }

    for missing_char in missing_characters {
        try_adding_character(missing_char)
    }

    clear(&missing_characters)

    characters := character_map

    char_rects : [dynamic]rp.Rect = {}
    defer delete(char_rects)

    total_area: i32 = 0

    glyph_padding : f32 = font_size / 2

    max_w : rp.Coord
    max_h : rp.Coord

    for character,bitmap in characters {
        rect := rp.Rect{
            w=rp.Coord(bitmap.width) + rp.Coord(glyph_padding),
            h=rp.Coord(bitmap.rows) + rp.Coord(glyph_padding),
        }

        if rect.w > max_w {
            max_w = rect.w
        }

        if rect.h > max_h {
            max_h = rect.h
        }

        fmt.println("Adding Rect:", rect.w, rect.h)

        append_elem(&char_rects, rect)

        total_area += i32(rect.w * rect.h)
    }

    ctx: rp.Context

    side := int(math.sqrt(f64(total_area)))

    width := i32(next_power_of_two(max(side, int(max_w * 2))))
    height := i32(next_power_of_two(int(max(total_area / width, i32(max_h * 2)))))

    num_nodes := width * 2

    nodes := make([]rp.Node, num_nodes)
    defer delete(nodes)

    rp.init_target(&ctx, width, height, &nodes[0], i32(num_nodes))

    success := rp.pack_rects(
        &ctx, 
        raw_data(char_rects),
        i32(len(char_rects))
    )

    fmt.println("Success? ", success == 1)
    fmt.println("WH:", width, height)
    fmt.println("Side:", side)
    fmt.println("Total area:", total_area)

    index := 0
    for character_code,character in characters {
        char_rect := char_rects[index]

        char_uv_map[character_code] = rect{
            x=f32(char_rect.x),
            y=f32(char_rect.y),
            width=f32(character.width),
            height=f32(character.rows),
        }

        index += 1
    }

    // Allocate the atlas buffer – one u8 per pixel for a 2560x2560 grayscale image.
    atlas := make([]u8, width * height)
    defer delete(atlas)

    index = 0
    for character_code, character in characters {
        rect := char_rects[index]

        if rect.was_packed == false {
            fmt.println("Skipping char", character_code, "— not packed properly")
            continue
        }

        index += 1

        x := i32(rect.x)
        y := i32(rect.y)
        w := i32(character.width)
        h := i32(character.rows)
        pitch := character.pitch

        if x < 0 || y < 0 || w <= 0 || h <= 0 || pitch <= 0 {
            continue
        }

        for row in 0..<h {
            src_offset := row * pitch
            dst_offset := (y + row) * width + x

            if dst_offset < 0 || dst_offset + w > i32(len(atlas)) || src_offset + w > i32(character.buffer_len) {
                fmt.println("Skipping char:", character_code, 
                    "row:", row,
                    "src_offset:", src_offset,
                    "dst_offset:", dst_offset,
                    "w:", w,
                    "pitch:", character.pitch,
                    "rows:", character.rows,
                    "buffer_len:", character.buffer_len)
                break

            }

            copy(atlas[dst_offset:dst_offset+w], character.buffer[src_offset:src_offset+w])
        }
    }
    char_uv_map_size = vec2{f32(width),f32(height)}

    gl.ActiveTexture(gl.TEXTURE0)
    font_texture_id_result, ok := upload_texture_buffer(raw_data(atlas), gl.RED, width, height)

    if !ok {
        fmt.println("Failed to upload font texture buffer.")
        return
    }

    font_texture_id = font_texture_id_result

    image.write_png(
        "atlas.png",
        width,height,1,raw_data(atlas),width,
    )

    free_character_buffers()
}

try_adding_character :: proc(character_code: u64) {
    if known_non_existing_chars[character_code] == true {
        return
    }

    if character_code in character_map {
        return
    }

    character, error_msg := gen_glyph_bitmap(character_code)

    if character == nil {
        known_non_existing_chars[character_code] = true

        return
    }

    character_map[character_code] = character

    return
}

find_char_in_faces :: proc(charcode: u64) -> (u32, ft.Face) {
    glyph_index : u32 = 0
    face : ft.Face

    for i in 0..<len(faces) {
        face = faces[i]

        glyph_index = ft.get_char_index(face, charcode)

        if glyph_index != 0 {
            break
        }
    }

    return glyph_index, face
}

gen_glyph_bitmap :: proc(charcode: u64) -> (character: ^Character, error_msg: string) {
    glyph_index, face := find_char_in_faces(charcode)
    if glyph_index == 0 do return nil, "glyph index 0"

    error : ft.Error

    error = ft.load_glyph(face, glyph_index, ft.Load_Flags{})
    if error != .Ok {
        return nil, "failed to load glyph"
    }
    
    error = ft.render_glyph(face.glyph, ft.Render_Mode.Normal)
    if error != .Ok {
        return nil, "Failed to render glyph"
    }

    orig_bmp := face.glyph.bitmap

    if orig_bmp.pixel_mode != 2 {
        return nil, "Wrong pixel mode"
    }

    size := int(orig_bmp.rows) * int(orig_bmp.pitch)
    if size <= 0 {
        return nil, "Invalid bitmap size"
    }

    new_buffer := make([]u8, size)

    // Create a slice from the raw pointer
    buffer_slice := mem.slice_ptr(orig_bmp.buffer, size)

    mem.copy(mem.raw_data(new_buffer), mem.raw_data(buffer_slice), size)

    char := new(Character)

    char^ = Character{
        buffer=new_buffer,
        buffer_len=len(new_buffer),
        width=orig_bmp.width,
        rows=orig_bmp.rows,
        pitch=orig_bmp.pitch,
        pixel_mode=orig_bmp.pixel_mode,
        advance=vec2{
            f32(face.glyph.advance.x),
            f32(face.glyph.advance.y),
        },
        offset=vec2{
            f32(face.glyph.bitmap_left),
            f32(face.glyph.bitmap_top),
        }
    }

    return char, ""
}
//
//generate_characters :: proc(faces: [dynamic]ft.Face) -> (map[u64]^Character) {
//    characters : map[u64]^Character = {}
//
//    for charcode in 0..=0x10FFFF { 
//        character, error_msg := gen_glyph_bitmap(u64(charcode))
//
//        if character == nil {
//            continue
//        }
//
//        characters[u64(charcode)] = character 
//    }
//
//    return characters
//}

Character :: struct {
    buffer: []u8,
    buffer_len: int,

    width:u32,
    rows:u32,
    pitch:i32,
    pixel_mode:u8,

    advance:vec2,
    offset:vec2,
}

@(private="package")
char_uv_map : map[u64]rect = {}

@(private="package")
char_uv_map_size : vec2

@(private="package")
character_map : map[u64]^Character  = {}

@(private="package")
report_missing_character :: proc(char_code: u64) {
    if char_code in known_non_existing_chars {
        return
    }

    append_elem(&missing_characters, char_code)
}

@(private="package")
update_fonts :: proc() {
    add_missing_characters()
}

@(private="package")
init_fonts :: proc() {
    load_all_fonts()
}

free_character_buffers :: proc() { 
    for char_code, character in character_map {
        delete(character.buffer)
    }
}

@(private="package")
clear_fonts :: proc() {
    for char_code, character in character_map {
        free(character)
    }

    delete_map(character_map)
    delete_map(char_uv_map)
    delete(faces)
    delete(missing_characters)
    delete(known_non_existing_chars)
}
