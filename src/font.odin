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
rect_pack_glyp_padding : f32 = 16

@(private="package")
font_size : f32 = 16

@(private="package")
line_height : f32 = 1.2

@(private="package")
library : ft.Library

@(private="package")
faces : [dynamic]ft.Face = {}

@(private="package")
font_texture_id : u32

MissingCharacterMap :: map[u64]bool

@(private="package")
known_non_existing_char_maps : map[f32]^MissingCharacterMap


MissingCharacter :: struct {
    char_code: u64,
    font_height: f32,
}

missing_characters : [dynamic]MissingCharacter

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

FontSize :: f32
CharacterCode :: u64

@(private="package")
CharUvMap :: map[CharacterCode]int

@(private="package")
char_uv_maps : map[FontSize]^CharUvMap

@(private="package")
char_uv_map_size : vec2

@(private="package")
CharacterMap :: map[CharacterCode]^Character

@(private="package")
character_maps : map[FontSize]^CharacterMap = {}

load_font :: proc(path: cstring) -> ft.Face {
    face : ft.Face
    
    error : ft.Error

    error = ft.init_free_type(&library)
    if error != .Ok do return nil

    error = ft.new_face(library, path, 0, &face)
    if error != .Ok do return nil

    error = ft.set_pixel_sizes(face, 0, 64)
    if error != .Ok do return nil

    return face
}

load_all_fonts :: proc() {
    // lower index higher importance
    font_list : []cstring = {
        "/usr/share/fonts/liberation/LiberationMono-Regular.ttf"
    }

    for font in font_list {
        face := load_font(font)

        append_elem(&faces, face)
    }
}

total_area: i32 = 0

atlas : []u8

@(private="package")
char_rects : [dynamic]rp.Rect = {}

@(private="package")
add_missing_characters :: proc() {
    if len(missing_characters) < 1 {
        return
    }

    when ODIN_DEBUG {
        fmt.println("Adding some missing characters..")
    }

    for missing_char in missing_characters {
        try_adding_character(missing_char)
    }

    max_w : rp.Coord
    max_h : rp.Coord


    for missing_char in missing_characters {
        char := get_char(missing_char.font_height, missing_char.char_code)

        // some chars didnt get added probably
        if char == nil {
            continue
        }

        char_rect := rp.Rect{
            w=rp.Coord(char.width) + rp.Coord(rect_pack_glyp_padding),
            h=rp.Coord(char.rows) + rp.Coord(rect_pack_glyp_padding),
        }

        if char_rect.w > max_w {
            max_w = char_rect.w
        }

        if char_rect.h > max_h {
            max_h = char_rect.h
        }

        append_elem(&char_rects, char_rect)

        char_uv_map := char_uv_maps[missing_char.font_height]

        if char_uv_map == nil {
            new_map := new(CharUvMap)

            char_uv_maps[missing_char.font_height] = new_map
            char_uv_map = new_map
        }
        
        char_uv_map[missing_char.char_code] = len(char_rects) - 1

        total_area += i32(char_rect.w * char_rect.h)
    }

    side := int(math.sqrt(f64(total_area)))

    width := i32(next_power_of_two(max(side, int(side * 2))))
    height := i32(next_power_of_two(int(max(total_area / width, i32(side * 2)))))

    atlas_size := width * height 

    has_atlas_grown := int(atlas_size) != len(atlas)

    if has_atlas_grown {
        atlas = make([]u8, width * height)

        when ODIN_DEBUG {
            fmt.println("Atlas resized to:", atlas_size)
        }
    }

    num_nodes := width

    nodes := make([]rp.Node, num_nodes)
    defer delete(nodes)

    ctx: rp.Context

    rp.init_target(&ctx, width, height, &nodes[0], i32(num_nodes))

    success := rp.pack_rects(
        &ctx, 
        raw_data(char_rects),
        i32(len(char_rects))
    )

    when ODIN_DEBUG {
        fmt.println("Success:", success == 1)
        fmt.println("WH:", width, height)
        fmt.println("Side:", side)
        fmt.println("Total area:", total_area)
    }

    /*
    index := 0
    for missing_char in missing_characters {        index += 1
    }
    */

    for font_size,character_map in character_maps {
        for character_code, char in character_map {
            if char == nil {
                continue
            }

            char_uv_map := char_uv_maps[font_size]
            index := char_uv_map[character_code]

            char_rect := char_rects[index]

            x := i32(char_rect.x)
            y := i32(char_rect.y)
            w := i32(char.width)
            h := i32(char.rows)
            pitch := char.pitch

            for row in 0..<h {
                src_offset := row * pitch
                dst_offset := (y + row) * width + x

                copy(
                    atlas[dst_offset:dst_offset+i32(w)],
                    char.buffer[src_offset:src_offset+i32(w)],
                )
            }
        }
    }

    clear(&missing_characters)

    char_uv_map_size = vec2{f32(width),f32(height)}

    upload_texture_buffer(raw_data(atlas), gl.RED, width, height, font_texture_id)

    fmt.println(char_uv_maps)

    fmt.println(char_rects)
    image.write_png(
        "atlas.png",
        width,height,1,raw_data(atlas),width,
    )

    //free_character_buffers()
}

try_adding_character :: proc(missing_char: MissingCharacter) {
    known_non_existing_chars := known_non_existing_char_maps[missing_char.font_height]

    if known_non_existing_chars[missing_char.char_code] == true {
        return
    }

    character_map := character_maps[missing_char.font_height]

    if missing_char.char_code in character_map {
        return
    }

    character, error_msg := gen_glyph_bitmap(missing_char.char_code, missing_char.font_height)

    if error_msg != "" {
        fmt.println("Char Code:", rune(missing_char.char_code))
        fmt.println(error_msg)
    }

    if character == nil {
        known_non_existing_chars[missing_char.char_code] = true

        return
    }

    character_map[missing_char.char_code] = character

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

gen_glyph_bitmap :: proc(charcode: u64, font_size: f32) -> (character: ^Character, error_msg: string) {
    glyph_index, face := find_char_in_faces(charcode)
    if glyph_index == 0 do return nil, "glyph index 0"

    error : ft.Error

    error = ft.set_pixel_sizes(face, 0, u32(font_size))
    if error != .Ok do return nil, "failed to set glyph pixel size"
    
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
    if size < 0 {
        return nil, "Invalid bitmap size"
    }

    new_buffer := make([]u8, size)

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

@(private="package")
report_missing_character :: proc(char_code: u64, font_height: f32) {
    known_non_existing_chars := known_non_existing_char_maps[font_height]

    if known_non_existing_chars == nil {
        new_map := new(MissingCharacterMap)

        when ODIN_DEBUG {
            fmt.println("Added missing char map for font_height:", font_height)
        }

        known_non_existing_char_maps[font_height] = new_map
        known_non_existing_chars = new_map
    }

    if char_code in known_non_existing_chars {
        return
    }

    char := MissingCharacter{
        char_code=char_code,
        font_height=font_height,
    }

    append_elem(&missing_characters, char)
}

@(private="package")
update_fonts :: proc() {
    add_missing_characters()
}

@(private="package")
init_fonts :: proc() {
    load_all_fonts()
    fmt.println("Fonts inited")
}

free_character_buffers :: proc() { 
    for size,character_map in character_maps {
        for char_code, character in character_map {
            //delete(character.buffer)
        }
    }
}

@(private="package")
clear_fonts :: proc() {
    for size,character_map in character_maps {
        for char_code, character in character_map {
            //free(character)
        }

        delete_map(character_map^)
        //free(character_map)
    }

    delete_map(character_maps)

    for size,char_uv_map in char_uv_maps {
        delete_map(char_uv_map^)
        //free(char_uv_map)
    }

    delete_map(char_uv_maps)

    for size,known_non_existing_char_map in known_non_existing_char_maps {
        delete(known_non_existing_char_map^)
        //free(known_non_existing_char_map)
    }

    delete(faces)
    delete(missing_characters)
    delete(char_rects)

    delete(known_non_existing_char_maps)
}

@(private="package")
get_char :: proc(font_height: f32, char_code: u64) -> ^Character {
    char_map := character_maps[font_height]

    if char_map == nil {
        new_map :=  new(CharacterMap)

        character_maps[font_height] = new_map
        char_map = new_map
    }

    character := char_map[char_code]

    if character == nil {
        report_missing_character(char_code, font_height) 

        return nil
    }

    return character
}
