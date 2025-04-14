#+private file
package main 
import gl "vendor:OpenGL"
import "core:fmt"
import "core:math"

@(private="package")
camera : [16]f32


@(private="package")
view : [16]f32


@(private="package")
camera_position := vec2{1,1}

@(private="package")
set_camera_ui :: proc() {
    near : f32 = -1
    far : f32 = 1

    left   : f32 = 0
    right  : f32 = fb_size.x
    top    : f32 = 0
    bottom : f32 = fb_size.y

    camera[0]  = 2.0 / (right - left)
    camera[5]  = 2.0 / (top - bottom)
    camera[10] = -2.0 / (far - near)

    camera[12] = -(right + left) / (right - left)
    camera[13] = -(top + bottom) / (top - bottom)
    camera[14] = -(far + near) / (far - near)

    camera[15] = 1.0
}

@(private="package")
set_view_ui :: proc() {
    view[0]  = 1.0
    view[1]  = 0.0
    view[2]  = 0.0
    view[3]  = 0.0

    view[4]  = 0.0
    view[5]  = 1.0
    view[6]  = 0.0
    view[7]  = 0.0

    view[8]  = 0.0
    view[9]  = 0.0
    view[10] = 1.0
    view[11] = 0.0

    view[12] = 0.0
    view[13] = 0.0
    view[14] = 0.0
    view[15] = 1.0
}

@(private="package")
update_camera :: proc() {
    gl.UseProgram(shader_id)
    gl.UniformMatrix4fv(projection_loc, 1, false, raw_data(camera[:]))
    gl.UniformMatrix4fv(view_loc, 1, false, raw_data(view[:]))
    gl.Uniform1i(first_texture_loc, 0)
}
