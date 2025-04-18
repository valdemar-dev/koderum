package main

status_bar_height : f32 = 20

status_bar_rect := rect{
    0,
    0,
    fb_size.x,
    status_bar_height,
}

draw_ui :: proc() {
    reset_rect_cache(&rect_cache)

    status_bar_rect = rect{
        0,
        0,
        fb_size.x,
        status_bar_height,
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

    draw_rects(&rect_cache)
}
