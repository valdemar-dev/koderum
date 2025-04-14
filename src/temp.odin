#+private file
package main

import gl "vendor:OpenGL"

@(private="package")
draw_temp :: proc() {
    gl.UseProgram(shader_id)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.Uniform1i(first_texture_loc, 0)

    pen := vec2{100,100}

    pen = add_text(&rect_cache, pen, vec4{1,1,1,1}, font_size, "asdf    a")
    draw_rects(&rect_cache)

    reset_rect_cache(&rect_cache)
}
