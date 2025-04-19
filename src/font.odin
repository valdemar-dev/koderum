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
font_size : f32 = 20

@(private="package")
line_height : f32 = 1.2

@(private="package")
library : ft.Library

@(private="package")
faces : [dynamic]ft.Face = {}

@(private="package")
font_texture_id : u32

NonExistingCharacterMap :: map[u64]bool

known_non_existing_char_maps_array : [dynamic]NonExistingCharacterMap
known_non_existing_char_maps : map[f32]int

MissingCharacter :: struct {
    char_code: u64,
    font_height: f32,
}

missing_characters : [dynamic]MissingCharacter

Character :: struct {
    buffer: [dynamic]u8,

    width:u32,
    rows:u32,
    pitch:i32,
    pixel_mode:u8,

    advance: vec2,
    offset: vec2,
}

FontSize :: f32
CharacterCode :: u64

@(private="package")
CharUvMap :: map[CharacterCode]int

@(private="package")
char_uv_maps_array : [dynamic]CharUvMap

@(private="package")
char_uv_maps : map[FontSize]int

@(private="package")
char_uv_map_size : vec2

@(private="package")
CharacterMap :: map[CharacterCode]^Character

@(private="package")
character_maps : map[FontSize]int

@(private="package")
character_maps_array : [dynamic]CharacterMap

@(private="package")
primary_font : ft.Face

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
        "/usr/share/fonts/liberation/LiberationMono-Regular.ttf",
        //"/usr/share/fonts/CascadiaMono/CaskaydiaMonoNerdFont-Regular.ttf",
    }

    for font in font_list {
        face := load_font(font)

        append_elem(&faces, face)
    }

    primary_font = faces[0]
}

total_area: i32 = 0

atlas : [dynamic]u8

@(private="package")
char_rects : [dynamic]rp.Rect = {}

width : i32
height : i32

max_w : rp.Coord
max_h : rp.Coord


@(private="package")
add_missing_characters :: proc() {
    if len(missing_characters) < 1 {
        return
    }

    when ODIN_DEBUG {
        fmt.println("Adding some missing characters..")
    }

    for missing_char in missing_characters {
        //char := get_char(missing_char.font_height, missing_char.char_code)
        char := try_adding_character(missing_char)

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

        uv_map_index := char_uv_maps[missing_char.font_height]

        if missing_char.font_height in char_uv_maps == false {
            new_map := make(CharUvMap)

            append(&char_uv_maps_array, new_map)

            new_index := len(char_uv_maps_array) - 1

            char_uv_maps[missing_char.font_height] = new_index

            uv_map_index = new_index
        }
        
        char_uv_map := &char_uv_maps_array[uv_map_index]
        assert(char_uv_map != nil)

        char_uv_map^[missing_char.char_code] = len(char_rects) - 1

        total_area += i32(char_rect.w * char_rect.h)
    }

    side := int(math.sqrt(f64(total_area)))

    width = i32(next_power_of_two(int(side * 2)))
    height = i32(next_power_of_two(int(side * 2)))

    atlas_size := width * height 

    has_atlas_grown := int(atlas_size) != len(atlas)

    atlas = make([dynamic]u8, width * height)
    defer delete(atlas)

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

    for font_size,index in character_maps {
        character_map := character_maps_array[index]
        
        for character_code, char in character_map {
            assert(char != nil)

            map_index := char_uv_maps[font_size]
            char_uv_map := char_uv_maps_array[map_index]

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

                assert(int(dst_offset + w) <= len(atlas))

                copy(
                    atlas[dst_offset:dst_offset+i32(w)],
                    char.buffer[src_offset:src_offset+i32(w)],
                )
            }
        }
    }

    char_uv_map_size = vec2{f32(width),f32(height)}

    upload_texture_buffer(raw_data(atlas), gl.RED, width, height, font_texture_id)

    when ODIN_DEBUG {
        fmt.println("Success! Added missing characters:", missing_characters)
    }

    clear(&missing_characters)

    /*
    image.write_png(
        "atlas.png",
        width,height,1,raw_data(atlas),width,
    )
    */

    //free_character_buffers()
}

try_adding_character :: proc(missing_char: MissingCharacter) -> ^Character {
    index := known_non_existing_char_maps[missing_char.font_height]
    known_non_existing_chars := known_non_existing_char_maps_array[index]

    char_map_index := character_maps[missing_char.font_height]
    character_map := &character_maps_array[char_map_index]

    assert(missing_char.char_code in character_map == false)

    character, error_msg := gen_glyph_bitmap(missing_char.char_code, missing_char.font_height)

    if error_msg != "" {
        fmt.println("Char Code:", rune(missing_char.char_code), missing_char.char_code)

        fmt.println(error_msg)
    }

    if character == nil {
        known_non_existing_chars[missing_char.char_code] = true

        return nil
    }

    character_map^[missing_char.char_code] = character

    return character
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

    load_flags := ft.Load_Flags{
        .Force_Autohint,
        .Load_Target_Light,
    }

    error = ft.load_glyph(face, glyph_index, load_flags)
    if error != .Ok {
        return nil, "failed to load glyph"
    }

    error = ft.render_glyph(face.glyph, ft.Render_Mode.Normal)
    if error != .Ok {
        return nil, "Failed to render glyph"
    }

    orig_bmp := face.glyph.bitmap

    if orig_bmp.pixel_mode != 2 { // 2 = FT_PIXEL_MODE_GRAY
        return nil, "Wrong pixel mode"
    }

    size := int(orig_bmp.rows) * int(orig_bmp.pitch)
    if size < 0 {
        return nil, "Invalid bitmap size"
    }

    new_buffer := make([dynamic]u8, size, context.allocator)

    buffer_slice := mem.slice_ptr(orig_bmp.buffer, size)

    mem.copy(raw_data(new_buffer), raw_data(buffer_slice), size)

    char := new(Character, context.allocator)

    char^ = Character{
        buffer=new_buffer,
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
        },
    }

    return char, ""
}

@(private="package")
report_missing_character :: proc(char_code: u64, font_height: f32) {
    index := known_non_existing_char_maps[font_height]

    if font_height in known_non_existing_char_maps == false {
        new_map := make(NonExistingCharacterMap)

        when ODIN_DEBUG {
            fmt.println("Added missing char map for font_height:", font_height)
        }

        append_elem(&known_non_existing_char_maps_array, new_map)

        new_index := len(known_non_existing_char_maps_array)-1

        known_non_existing_char_maps[font_height] = new_index 
        index = new_index 
    }

    known_non_existing_chars := known_non_existing_char_maps_array[index]

    if char_code in known_non_existing_chars {
        return
    }

    known_non_existing_chars[char_code] = true
    known_non_existing_char_maps_array[index] = known_non_existing_chars

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
}

@(private="package")
clear_fonts :: proc() {
    for size,index in character_maps {
        character_map := character_maps_array[index]

        for char_code, character in character_map {
            delete(character.buffer)

            if character != nil {
                free(character, context.allocator)
            }
        }

        delete(character_map)
    }

    for size,index in char_uv_maps {
        delete(char_uv_maps_array[index])
    }

    for size,known_non_existing_char_map in known_non_existing_char_maps {
        delete(known_non_existing_char_maps_array[known_non_existing_char_map])
    }

    delete(known_non_existing_char_maps_array)
    delete(character_maps)
    delete(char_uv_maps)
    delete(faces)
    delete(missing_characters)
    delete(char_rects)
    delete(known_non_existing_char_maps)

    delete(character_maps_array)
    delete(char_uv_maps_array)
}

@(private="package")
get_char :: proc(font_height: f32, char_code: u64) -> ^Character {
    index := character_maps[font_height]

    if font_height in character_maps == false {
        new_map := make(CharacterMap, context.allocator)

        append(&character_maps_array, new_map)

        new_index := len(character_maps_array) - 1

        character_maps[font_height] = new_index
        index = new_index
    }

    char_map := character_maps_array[index]

    character, ok := char_map[char_code]

    if character == nil {
        report_missing_character(char_code, font_height) 

        return nil
    }

    return character
}
