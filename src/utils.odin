#+feature dynamic-literals
package main
import "core:fmt"
import ft "../../alt-odin-freetype"
import "core:math"

vec2 :: struct {
    x: f32,
    y: f32,
}

vec3 :: struct {
    x: f32,
    y: f32,
    z: f32,
}

vec4 :: struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
}

rect :: struct {
    x:f32,
    y:f32,
    width:f32,
    height:f32,
}

RectCache :: struct {
    vertices: [dynamic]f32,
    indices: [dynamic]u32,

    raw_vertices: rawptr,
    raw_indices: rawptr,

    vertices_size: int,
    indices_size: int,

    vertex_offset: u32,
}

mat2 :: struct {
	a: f32,
	b: f32,
	c: f32,
	d: f32,
}

no_texture := rect{-1,-1,-1,-1}

next_power_of_two :: proc(n: int) -> int {
    p := 1
    for p < n do p *= 2
    return p
}

smooth_lerp :: proc(current, target, smoothing_factor: f32, frame_time: f32) -> f32 {
    return current + (target - current) * (1 - math.pow(2.71828, -smoothing_factor * frame_time))
}   

SlidingBuffer :: struct($Type: typeid) {
    data: ^Type,
    length: int,
    count: int,
}

push :: proc(sb: ^SlidingBuffer($TB), value: $T) {
    if sb.count < sb.length {
        for i := sb.count; i > 0; i -= 1 {
            sb.data[i] = sb.data[i - 1];
        }

        sb.data[0] = value;
        sb.count += 1;
    } else {
        for i := sb.length - 1; i > 0; i -= 1 {
            sb.data[i] = sb.data[i - 1];
        }

        sb.data[0] = value;
    }
}
