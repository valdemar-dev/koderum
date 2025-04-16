package main

draw_ui :: proc() {
    reset_rect_cache(&rect_cache)

    bar_height : f32 = 20

    bottom_bar_rect := rect{
        0,
        fb_size.y - bar_height,
        fb_size.x,
        bar_height,
    }

    add_rect(&rect_cache,
        bottom_bar_rect,
        no_texture,
        colour_bg_lighter,
    )

    text_pos := vec2{
        bottom_bar_rect.x,
        bottom_bar_rect.y,
    }

    add_text(&rect_cache,
        text_pos,
        vec4{1,1,1,1},
        20,
        "hi"
    )


    draw_rects(&rect_cache)
}
