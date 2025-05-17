package main
import gl "vendor:OpenGL"

upload_texture_buffer :: proc(buffer: rawptr, format: u32, width, height: i32, texture_id: u32) -> (id: u32, ok: bool) { 
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, texture_id)

    gl.TexImage2D(gl.TEXTURE_2D, 0, i32(format), width, height, 0, format, gl.UNSIGNED_BYTE, buffer)
   // gl.GenerateMipmap(gl.TEXTURE_2D)

    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

   // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER)
   // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER)

    return texture_id, true   
} 
