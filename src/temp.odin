#+private file
package main

import gl "vendor:OpenGL"

@(private="package")
draw_temp :: proc() {
    gl.UseProgram(shader_id)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.Uniform1i(first_texture_loc, 0)

    pen := vec2{100,100}

    pen = add_text(&rect_cache, pen, vec4{1,1,1,1}, 128, "This is REALLY BIG TEXT")

    pen.x = 100

    pen = add_text(&rect_cache, pen, vec4{1,1,1,1}, 8, "This is really small text!")

    pen.x = 100

    pen = add_text(&rect_cache, pen, vec4{1,1,1,1}, 16, "This is regularly sized text.")

    pen.x = 100

    pen = add_text(&rect_cache, pen, vec4{1,1,1,1}, 32, "я люблю есть кошек")
    pen = add_text(&rect_cache, pen, vec4{1,1,1,1}, 32, "我喜欢吃猫")

    draw_rects(&rect_cache)

    reset_rect_cache(&rect_cache)
}
