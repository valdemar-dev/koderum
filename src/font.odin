package main

import ft "../../alt-odin-freetype"
import "core:fmt"
import "core:mem"
import gl "vendor:OpenGL"
import "core:math"
import "core:strings"
import "core:os"

import rp "vendor:stb/rect_pack"
import image "vendor:stb/image"

import "core:c"

@(private="package")
rect_pack_glyp_padding : f32 = 16

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

@(private="package")
Character :: struct {
    buffer: [dynamic]u8,

    width: u32,
    rows: u32,
    pitch: i32,
    pixel_mode: u8,

    advance: vec2,
    offset: vec2,
}

FontSize :: f32
CharacterCode :: u64

PLANE_ZERO_MAX :: 65_536

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

load_font :: proc(path: cstring) -> (face: ft.Face, err: ft.Error) {
    error : ft.Error

    error = ft.init_free_type(&library)
    if error != .Ok do return nil, error

    error = ft.new_face(library, path, 0, &face)
    if error != .Ok do return nil, error

    face_flags := transmute(ft.Face_Flags)face.face_flags
    if .Fixed_Sizes in face_flags {
        if face.num_fixed_sizes == 0 {
            return nil, .Invalid_Argument
        }
        error = ft.select_size(face, 0)
        if error != .Ok do return nil, error
    } else {
        error = ft.set_pixel_sizes(face, 0, 64)
        if error != .Ok do return nil, error
    }

    return face, .Ok
}

@(private="package")
font_list : [dynamic]string = {}

load_all_fonts :: proc() {
    context = global_context
    
    for font in font_list {
        c_string := cstring(raw_data(font))
        
        if (os.exists(font) == false) {
            fmt.println("Font file doesn't exist!", font)
            
            continue
        }
        
        fmt.println("Loading font face..", font)

        face, err := load_font(c_string)

        if face == nil {
            fmt.println(
                "Failed to load font file,",
                font,
                "Got Err:",
                err,
            )

            continue
        }
        
        fmt.println("Loaded font:", face)

        append(&faces, face)
    }

    if len(faces) == 0 {
        panic("No fonts could be loaded.")
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
    context = global_context
    
    clear(&atlas)    

    if len(missing_characters) < 1 {
        return
    }

    when ODIN_DEBUG {
        fmt.println("Adding missing characters..")
    }

    for missing_char in missing_characters {
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

    atlas = make([dynamic]u8, width * height * 4)
    defer delete(atlas)

    num_nodes := width

    nodes := make([]rp.Node, num_nodes)
    defer delete(nodes)

    ctx: rp.Context

    rp.init_target(&ctx, width, height, &nodes[0], i32(num_nodes))

    rp.pack_rects(
        &ctx, 
        raw_data(char_rects),
        i32(len(char_rects))
    )

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
                dst_offset := (y + row) * width * 4 + x * 4

                assert(int(dst_offset + w * 4) <= len(atlas))

                copy(
                    atlas[dst_offset:dst_offset + i32(w) * 4],
                    char.buffer[src_offset:src_offset + i32(w) * 4],
                )
            }
        }
    }

    char_uv_map_size = vec2{f32(width),f32(height)}

    upload_texture_buffer(raw_data(atlas), gl.RGBA, width, height, font_texture_id)

    when ODIN_DEBUG {
        fmt.println("Success! Added missing characters.")
    }

    clear(&missing_characters)
}

try_adding_character :: proc(missing_char: MissingCharacter) -> ^Character {
    context = global_context

    index := known_non_existing_char_maps[missing_char.font_height]

    known_non_existing_chars := known_non_existing_char_maps_array[index]

    char_map_index := character_maps[missing_char.font_height]
    character_map := &character_maps_array[char_map_index]

    assert(missing_char.char_code in character_map == false)

    character, error_msg := gen_glyph_bitmap(missing_char.char_code, missing_char.font_height)

    when ODIN_DEBUG {
        if error_msg != "" {
            fmt.println("Char Code:", rune(missing_char.char_code), missing_char.char_code)
            fmt.println(error_msg)
        }
    }

    if character == nil {
        known_non_existing_chars[missing_char.char_code] = true

        return nil
    }

    character_map^[missing_char.char_code] = character

    return character
}

find_char_in_faces :: proc(charcode: u64) -> (glyph_index: u32, face: ft.Face) {
    context = global_context

    for i in 0..<len(faces) {
        f := faces[i]
        g_index := ft.get_char_index(f, charcode)
        if g_index != 0 {
            glyph_index = g_index
            face = f
                
            break
        }
    }

    return glyph_index, face
}

gen_glyph_bitmap :: proc(charcode: u64, font_size: f32) -> (character: ^Character, error_msg: string) {
    context = global_context

    glyph_index, face := find_char_in_faces(charcode)
    
    if glyph_index == 0 {
        return nil, "no glyph"
    }

    face_flags := transmute(ft.Face_Flags)face.face_flags
    has_fixed_sizes := .Fixed_Sizes in face_flags
    has_color := .Color in face_flags

    target_px_size := u32(font_size)
    scale_factor := f32(1.0)
    rendered_size: f32

    error : ft.Error

    if has_fixed_sizes {
        if face.num_fixed_sizes == 0 {
            return nil, "Fixed-size font with no available sizes"
        }
        error = ft.select_size(face, 0)
        if error != .Ok {
            return nil, "Failed to select fixed size"
        }
        rendered_size = f32(face.size.metrics.height >> 6)
        scale_factor = font_size / rendered_size
    } else {
        error = ft.set_pixel_sizes(face, 0, target_px_size)
        if error != .Ok {
            return nil, "Failed to set pixel size"
        }
        rendered_size = font_size
    }

    load_flags := i32(ft.Load_Flags{.Render})
    if has_color {
        load_flags |= i32(ft.Load_Flags{.Color})
    }
       
    error = ft.load_glyph(face, glyph_index, load_flags)
    if error != .Ok {
        return nil, "Failed to load glyph"
    }

    error = ft.render_glyph(face.glyph, ft.Render_Mode.Normal)
    if error != .Ok {
        return nil, "Failed to render glyph"
    }

    orig_bmp := face.glyph.bitmap
 
    channels: int = 4
    temp_buffer : [dynamic]u8
    orig_width: u32 = orig_bmp.width
    orig_rows: u32 = orig_bmp.rows
    orig_pitch : i32
    pixel_mode := orig_bmp.pixel_mode

    if orig_bmp.rows == 0 || orig_bmp.width == 0 {
        temp_buffer = {}
        orig_pitch = orig_bmp.pitch
        pixel_mode = u8(ft.Pixel_Mode.Gray) if !has_color else u8(ft.Pixel_Mode.Bgra)
    } else {
        if orig_bmp.pixel_mode == u8(ft.Pixel_Mode.Gray) {
            orig_pitch = i32(orig_width) * 4
            temp_buffer = make([dynamic]u8, int(orig_rows) * int(orig_pitch))
            
            for row: u32 = 0; row < orig_rows; row += 1 {
                src_offset := int(row) * int(orig_bmp.pitch)
                dst_offset := int(row) * int(orig_pitch)
                
                src := ([^]u8)(orig_bmp.buffer)[src_offset:]
                dst := temp_buffer[dst_offset:]
                
                for x: u32 = 0; x < orig_width; x += 1 {
                    gray := src[x]
                    dst[x*4 + 0] = gray
                    dst[x*4 + 1] = gray
                    dst[x*4 + 2] = gray
                    dst[x*4 + 3] = 255
                }
            }
        } else if orig_bmp.pixel_mode == u8(ft.Pixel_Mode.Bgra) {
            orig_pitch = orig_bmp.pitch
            temp_buffer = make([dynamic]u8, int(orig_rows) * int(orig_pitch))
            
            for row: u32 = 0; row < orig_rows; row += 1 {
                src_offset := int(row) * int(orig_bmp.pitch)
                dst_offset := src_offset // same
                
                src := ([^]u8)(orig_bmp.buffer)[src_offset:]
                dst := temp_buffer[dst_offset:]
                
                for x: u32 = 0; x < orig_width; x += 1 {
                    dst[x*4 + 0] = src[x*4 + 2]
                    dst[x*4 + 1] = src[x*4 + 1]
                    dst[x*4 + 2] = src[x*4 + 0]
                    dst[x*4 + 3] = src[x*4 + 3]
                }
            }
        } else {
            return nil, "Unsupported pixel mode"
        }
    }

    if scale_factor != 1.0 && orig_width > 0 && orig_rows > 0 {
        new_width_i32 := i32(math.round_f32(f32(orig_width) * scale_factor))
        new_height_i32 := i32(math.round_f32(f32(orig_rows) * scale_factor))
        if new_width_i32 < 1 || new_height_i32 < 1 {
            delete(temp_buffer)
            return nil, "Scaled size too small"
        }
        new_width := u32(new_width_i32)
        new_height := u32(new_height_i32)
        resize_buffer := make([dynamic]u8, int(new_height) * int(new_width_i32) * channels)
        resize_success := image.resize(
            raw_data(temp_buffer),
            i32(orig_width),
            i32(orig_rows),
            orig_pitch,
            raw_data(resize_buffer),
            new_width_i32,
            new_height_i32,
            0,
            image.datatype.UINT8,
            i32(channels),
            true,
            0,
            image.edge.CLAMP,
            image.edge.CLAMP,
            image.filter.DEFAULT,
            image.filter.DEFAULT,
            image.colorspace.LINEAR,
            nil
        )

        if resize_success == 0 {
            delete(temp_buffer)
            delete(resize_buffer)
            return nil, "Failed to resize bitmap"
        }
        delete(temp_buffer)
        temp_buffer = resize_buffer
        orig_pitch = i32(new_width) * i32(channels)
        orig_width = new_width
        orig_rows = new_height
    }
    
    char := new(Character)

    char^ = Character{
        buffer=temp_buffer,
        width=orig_width,
        rows=orig_rows,
        pitch=orig_pitch,
        pixel_mode=pixel_mode,
        advance=vec2{
            (f32(face.glyph.advance.x) / 64) * scale_factor,
            (f32(face.glyph.advance.y) / 64) * scale_factor,
        },
        offset=vec2{
            f32(face.glyph.bitmap_left) * scale_factor,
            f32(face.glyph.bitmap_top) * scale_factor,
        },
    }

    return char, ""
}

@(private="package")
report_missing_character :: proc(char_code: u64, font_height: f32) {
    context = global_context

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
    fmt.println("Successfully initialized fonts!")
}

free_character_buffers :: proc() { 
}

@(private="package")
clear_fonts :: proc() {
    context = global_context
    
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

    for fl in font_list {
        delete(fl)
    }
}

@(private="package")
get_char :: proc(font_height: f32, char_code: u64) -> ^Character {
    context = global_context

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

@(private="package")
get_char_map :: proc(font_height: f32) -> ^CharacterMap {
    context = global_context

    index := character_maps[font_height]

    if font_height in character_maps == false {
        new_map := make(CharacterMap)

        append(&character_maps_array, new_map)

        new_index := len(character_maps_array) - 1

        character_maps[font_height] = new_index
        index = new_index
    }

    char_map := &character_maps_array[index]

    return char_map
}

@(private="package")
get_char_with_char_map :: proc(
    char_map: ^CharacterMap,
    font_height: f32,
    char_code: u64,
) -> ^Character {
    context = global_context

    character, ok := char_map^[char_code]

    if character == nil || ok == false {
        report_missing_character(char_code, font_height) 

        return nil
    }

    return character
}


/*
#+private file
package main

import ft "../../alt-odin-freetype"
import "core:fmt"
import "core:mem"
import gl "vendor:OpenGL"
import "core:math"
import "core:strings"
import "core:os"

import rp "vendor:stb/rect_pack"
import image "vendor:stb/image"

import "core:c"

@(private="package")
rect_pack_glyp_padding : f32 = 16

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

@(private="package")
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

load_font :: proc(path: cstring) -> (face: ft.Face, err: ft.Error) {
    error : ft.Error

    error = ft.init_free_type(&library)
    if error != .Ok do return nil, error

    error = ft.new_face(library, path, 0, &face)
    if error != .Ok do return nil, error

    error = ft.set_pixel_sizes(face, 0, 64)
    if error != .Ok do return nil, error

    return face, .Ok
}

@(private="package")
font_list : [dynamic]string = {}

load_all_fonts :: proc() {
    context = global_context
    
    for font in font_list {
        c_string := cstring(raw_data(font))
        
        if (os.exists(font) == false) {
            fmt.println("Font file doesn't exist!", font)
            
            continue
        }
        
        fmt.println("Loading font face..", font)

        face, err := load_font(c_string)

        if face == nil {
            fmt.println(
                "Failed to load font file,",
                font,
                "Got Err:",
                err,
            )

            continue
        }
        
        fmt.println("Loaded font:", face)

        append(&faces, face)
    }

    if len(faces) == 0 {
        panic("No fonts could be loaded.")
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
    context = global_context
    
    clear(&atlas)    

    if len(missing_characters) < 1 {
        return
    }

    when ODIN_DEBUG {
        fmt.println("Adding missing characters..")
    }

    for missing_char in missing_characters {
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

    atlas = make([dynamic]u8, width * height)
    defer delete(atlas)

    num_nodes := width

    nodes := make([]rp.Node, num_nodes)
    defer delete(nodes)

    ctx: rp.Context

    rp.init_target(&ctx, width, height, &nodes[0], i32(num_nodes))

    rp.pack_rects(
        &ctx, 
        raw_data(char_rects),
        i32(len(char_rects))
    )

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
        fmt.println("Success! Added missing characters.")
    }

    clear(&missing_characters)
}

try_adding_character :: proc(missing_char: MissingCharacter) -> ^Character {
    context = global_context

    index := known_non_existing_char_maps[missing_char.font_height]
    known_non_existing_chars := known_non_existing_char_maps_array[index]

    char_map_index := character_maps[missing_char.font_height]
    character_map := &character_maps_array[char_map_index]

    assert(missing_char.char_code in character_map == false)

    character, error_msg := gen_glyph_bitmap(missing_char.char_code, missing_char.font_height)

    when ODIN_DEBUG {
        if error_msg != "" {
            fmt.println("Char Code:", rune(missing_char.char_code), missing_char.char_code)
            fmt.println(error_msg)
        }

    }

    if character == nil {
        known_non_existing_chars[missing_char.char_code] = true

        return nil
    }

    character_map^[missing_char.char_code] = character

    return character
}

find_char_in_faces :: proc(charcode: u64) -> (u32, ft.Face) {
    context = global_context

    glyph_index : u32 = 0
    face : ft.Face

    for i in 0..<len(faces) {
        face = faces[i]

        when ODIN_OS == .Windows {
            glyph_index = ft.get_char_index(face, u32(charcode))
        }

        when ODIN_OS == .Linux {
            glyph_index = ft.get_char_index(face, charcode)
        }
        
        if glyph_index != 0 {
            break
        }
    }

    return glyph_index, face
}

gen_glyph_bitmap :: proc(charcode: u64, font_size: f32) -> (character: ^Character, error_msg: string) {
    context = global_context

    glyph_index, face := find_char_in_faces(charcode)
    

    error : ft.Error

    error = ft.set_pixel_sizes(face, 0, u32(font_size))
    if error != .Ok do return nil, "failed to set glyph pixel size"

    load_flags := int(ft.Load_Flags{
        .Render,
    })

    flags := i32(ft.Load_Flags.Render)
       
    error = ft.load_glyph(face, glyph_index, flags)
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

    new_buffer := make([dynamic]u8, size)

    buffer_slice := mem.slice_ptr(orig_bmp.buffer, size)

    mem.copy(raw_data(new_buffer), raw_data(buffer_slice), size)

    char := new(Character)

    char^ = Character{
        buffer=new_buffer,
        width=orig_bmp.width,
        rows=orig_bmp.rows,
        pitch=orig_bmp.pitch,
        pixel_mode=orig_bmp.pixel_mode,
        advance=vec2{
            math.round_f32(f32(face.glyph.advance.x / 64)),
            math.round_f32(f32(face.glyph.advance.y)),
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
    context = global_context

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
    fmt.println("Successfully initialized fonts!")
}

free_character_buffers :: proc() { 
}

@(private="package")
clear_fonts :: proc() {
    context = global_context
    
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

    for fl in font_list {
        delete(fl)
    }
}

@(private="package")
get_char :: proc(font_height: f32, char_code: u64) -> ^Character {
    context = global_context

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

@(private="package")
get_char_map :: proc(font_height: f32) -> ^CharacterMap {
    context = global_context

    index := character_maps[font_height]

    if font_height in character_maps == false {
        new_map := make(CharacterMap)

        append(&character_maps_array, new_map)

        new_index := len(character_maps_array) - 1

        character_maps[font_height] = new_index
        index = new_index
    }

    char_map := &character_maps_array[index]

    return char_map
}

@(private="package")
get_char_with_char_map :: proc(
    char_map: ^CharacterMap,
    font_height: f32,
    char_code: u64,
) -> ^Character {
    context = global_context

    character, ok := char_map^[char_code]

    if character == nil || ok == false {
        report_missing_character(char_code, font_height) 

        return nil
    }

    return character
}
*/
