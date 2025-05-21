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

array_find :: proc(arr: []$T, match_proc: proc(value: T) -> bool) -> ^T {
    for value in array {
        if match_proc(value) {
            return &value
        }
    }

    return nil
}

hex_string_to_vec4 :: proc(hex_str: string) -> vec4 {
    if len(hex_str) != 8 {
        return vec4{0, 0, 0, 1}
    }
    hex: u32 = 0
    for i in 0..<8 {
        digit := hex_str[i]
        hex_value: u32
        if '0' <= digit && digit <= '9' {
            hex_value = u32(digit - '0')
        } else if 'A' <= digit && digit <= 'F' {
            hex_value = u32(digit - 'A' + 10)
        } else if 'a' <= digit && digit <= 'f' {
            hex_value = u32(digit - 'a' + 10)
        } else {
            return vec4{0, 0, 0, 1}
        }
        hex = (hex << 4) | hex_value
    }
    r := f32((hex >> 24) & 0xFF) / 255.0
    g := f32((hex >> 16) & 0xFF) / 255.0
    b := f32((hex >> 8)  & 0xFF) / 255.0
    a := f32((hex)       & 0xFF) / 255.0
    return vec4{r, g, b, a}
}

rune_in_arr :: proc(el: rune, arr: []rune) -> (ok: bool) {
    for element in arr {
        if element == el {
            return true
        }
    }

    return false
}

contains_runes :: proc(main: []rune, subset: []rune) -> (found: bool, start: int) {
    n := len(main)
    m := len(subset)
    if m == 0 || m > n {
        return false, -1
    }

    for i in 0..<(n - m + 1) {
        ok := true

        for j in 0..<m {
            if main[i + j] != subset[j] {
                ok = false
                break
            }
        }
        if ok {
            return true, i
        }
    }
    return false, -1
}
