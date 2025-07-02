package main

import "core:math"
import "core:strconv"
import "core:strings"
import "vendor:glfw"

buf : [8]byte = {}

draw_debug :: proc() {
    str := strings.concatenate({
        "Line:",
        strings.clone(strconv.itoa(buf[:], buffer_cursor_line), context.temp_allocator),
        ",",
        strings.clone(strconv.itoa(buf[:], highlight_start_line), context.temp_allocator),

        "\nChar:",
        strings.clone(strconv.itoa(buf[:], buffer_cursor_char_index), context.temp_allocator),
        ",",
        strings.clone(strconv.itoa(buf[:], highlight_start_char), context.temp_allocator),
        "\nFPS:",
        strings.clone(strconv.ftoa(buf[:], f64(1 / frame_time), 'f', 10, 64), context.temp_allocator),
    }, context.temp_allocator)
    
    normal_text := math.round_f32(font_base_px * normal_text_scale)

    add_text(&rect_cache,
        vec2{0,0},
        TEXT_MAIN,
        normal_text,
        str,
        1000,
        false,
        -1,
        false,
        true,
    )

    draw_rects(&rect_cache)

    reset_rect_cache(&rect_cache)
}

handle_debug_input :: proc() {
    if is_key_pressed(glfw.KEY_1) {
        alert := new(Alert)
        alert^ = Alert{
            title="Installing Tree-Sitter",
            content="This may take a while..",
            show_seconds=5,
            remaining_seconds=5,
        }

        append(&alert_queue, alert)
    }
   
}
