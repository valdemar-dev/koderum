#+feature dynamic-literals
package main
import "core:fmt"
import ft "../../alt-odin-freetype"
import "core:math"
import "core:encoding/json"
import "core:unicode/utf8"
import "core:strings"
import "core:os/os2"

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

SHIFT : i32 : 1
CTRL : i32 : 2
CTRL_SHIFT : i32 : 3
ALT : i32 : 4

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

contains_runes :: proc(main: string, subset: []rune) -> (found: bool, start: int) {
    n := len(main)
    m := len(subset)
    if m == 0 || m > n {
        return false, -1
    }

    for i in 0..<(n - m + 1) {
        ok := true

        for j in 0..<m {
            if main[i + j] != u8(subset[j]) {
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

value_to_str_array :: proc(arr: json.Array) -> []string {
    values := make([dynamic]string)
    
    for value in arr {
        str_value, str_ok := value.(string)
        
        if !str_ok {
            panic("Value in str array is not a str.")
        }
        
        append(&values, strings.clone(str_value))
    }
    
    return values[:]
}

byte_offset_to_rune_index :: proc(line: string, byte_offset: int) -> int {
    rune_index := 0
    i := 0
    for i < byte_offset && i < len(line) {
        _, size := utf8.decode_rune(line[i:])
        i += size
        rune_index += 1
    }
    return rune_index
}

encode_uri_component :: proc(path: string) -> string {
    buf := make([dynamic]rune)

    is_unreserved := proc(c: rune) -> bool {
        return (c >= 'A' && c <= 'Z') ||
               (c >= 'a' && c <= 'z') ||
               (c >= '0' && c <= '9') ||
               c == '-' || c == '_' || c == '.' || c == '~'
    }

    hex_digits := "0123456789ABCDEF"

    for c in path {
        if is_unreserved(c) || c == '/' {
            append(&buf, c)
        } else {
            append(&buf, '%')
            append(&buf, rune(hex_digits[c >> 4]))
            append(&buf, rune(hex_digits[c & 0xF]))
        }
    }

    
    defer delete(buf)

    return utf8.runes_to_string(buf[:])
}

run_program :: proc(
    command: []string,
    env: []string,
    working_dir: string = "",
) -> os2.Error {
    desc := os2.Process_Desc{
        working_dir,
        command,
        env,
        nil,
        nil,
        nil,
    }
    
    when ODIN_DEBUG {
        fmt.println("Running program: ", command)
    }
    
    state, stdout, stderr, error := os2.process_exec(desc, context.allocator)
    
    when ODIN_DEBUG {
        fmt.println("Result of program", command)
        fmt.println(state)
    }

    return error
}

is_point_in_rect :: proc(p: vec2, r: rect) -> bool {
	return p.x >= r.x &&
	       p.y >= r.y &&
	       p.x <= r.x + r.width &&
	       p.y <= r.y + r.height
}

get_substring_indices :: proc(haystack: string, needle: string) -> [dynamic]int {
    if len(needle) == 0 || len(haystack) < len(needle) {
        return {}
    }

    indices := make([dynamic]int)
    
    for i in 0..<len(haystack) - len(needle) + 1 {
        if haystack[i : i + len(needle)] == needle {
            append(&indices, i)
        }
    }
    return indices
}

color_index_to_color :: proc(color_index : int) -> ^vec4 {
    switch color_index {
    case 0:
        return &TOKEN_COLOR_00
    case 1:
        return &TOKEN_COLOR_01
    case 2:
        return &TOKEN_COLOR_02
    case 3:
        return &TOKEN_COLOR_03
    case 4:
        return &TOKEN_COLOR_04
    case 5:
        return &TOKEN_COLOR_05
    case 6:
        return &TOKEN_COLOR_06
    case 7:
        return &TOKEN_COLOR_07
    case 8:
        return &TOKEN_COLOR_08
    case 9:
        return &TOKEN_COLOR_09
    case 10:
        return &TOKEN_COLOR_10
    case 11:
        return &TOKEN_COLOR_11
    case 12:
        return &TOKEN_COLOR_12
    case 13:
        return &TOKEN_COLOR_13
    case 14:
        return &TOKEN_COLOR_14
    case:
        return nil
    }
}