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

    draw_rects(&rect_cache)
}
