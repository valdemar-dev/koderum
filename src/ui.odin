package main

import "core:fmt"
import "vendor:glfw"
import "core:unicode/utf8"
import ft "../../alt-odin-freetype"

ui_general_font_size :: 20

status_bar_rect := rect{
    0,
    0,
    fb_size.x,
    0,
}

ui_sliding_buffer := SlidingBuffer([16]rune){
    length=16,
    data=new([16]rune),
}

@(private="package")
handle_ui_input :: proc(key, scancode, action, mods: i32) {
    if action == glfw.RELEASE {
        return
    }

    key_name := glfw.GetKeyName(key, scancode)

    for r in key_name {
        push(&ui_sliding_buffer, r)
    }

    if mods != 0 {
        value : string

        switch mods {
        case 1:
            value = "Shift+"
            break
        case 2:
            value = "Ctrl+"
        }

        #reverse for r in value {
            push(&ui_sliding_buffer, r)
        }
    }
}

draw_ui :: proc() {
    reset_rect_cache(&rect_cache)

    error := ft.set_pixel_sizes(primary_font, 0, u32(ui_general_font_size))
    if error != .Ok do return

    asc := primary_font.size.metrics.ascender >> 6
    desc := primary_font.size.metrics.descender >> 6

    status_bar_height := asc - desc

    status_bar_rect = rect{
        0,
        0,
        fb_size.x,
        f32(status_bar_height),
    }

    add_rect(&rect_cache,
        status_bar_rect,
        no_texture,
        colour_bg_lighter,
    )

    text_pos := vec2{
        status_bar_rect.x,
        status_bar_rect.y,
    }

    mode_string : string

    switch input_mode {
    case .COMMAND:
        mode_string = "Command"
    case .TEXT:
        mode_string = "Text Input"
    }

    add_text(&rect_cache,
        text_pos,
        vec4{1,1,1,1},
        20,
        mode_string,
    )

    buf_data_string := utf8.runes_to_string(ui_sliding_buffer.data[:])
    defer delete(buf_data_string )

    add_text(&rect_cache,
        vec2{
            status_bar_rect.x + status_bar_rect.width - 100,
            status_bar_rect.y,
        },
        vec4{1,1,1,1},
        ui_general_font_size,
        buf_data_string,
    )

    draw_rects(&rect_cache)
}
