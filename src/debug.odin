package main

import "core:strconv"
import "core:strings"

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

    add_text(&rect_cache,
        vec2{0,0},
        TEXT_MAIN,
        ui_general_font_size,
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
