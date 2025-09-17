#+feature dynamic-literals
package main
import "core:fmt"
import "core:sort"
import ft "../../alt-odin-freetype"
import "core:math"
import "core:encoding/json"
import "core:unicode/utf8"
import "core:strings"
import "core:os/os2"
import "vendor:glfw"

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

smooth_lerp_vec4 :: proc(current, target: vec4, smoothing_factor, frame_time: f32) -> vec4 {
    t := 1 - math.pow(2.71828, -smoothing_factor * frame_time)
    return vec4{
        current.x + (target.x - current.x) * t,
        current.y + (target.y - current.y) * t,
        current.z + (target.z - current.z) * t,
        current.w + (target.w - current.w) * t,
    }
}


SlidingBuffer :: struct($Type: typeid) {
    data: ^Type,
    length: int,
    count: int,
}

push :: proc(sb: ^SlidingBuffer($TB), value: $T) -> (T, bool) {
    if sb.count < sb.length {
        for i := sb.count; i > 0; i -= 1 {
            sb.data[i] = sb.data[i - 1];
        }

        sb.data[0] = value;
        sb.count += 1;
        return value, false;
    } else {
        removed := sb.data[sb.length - 1];
        for i := sb.length - 1; i > 0; i -= 1 {
            sb.data[i] = sb.data[i - 1];
        }

        sb.data[0] = value;
        return removed, true;
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

sanitize_ansi_string :: proc(text: string) -> (sanitized: [dynamic]u8, escapes: [dynamic]string) {
    i := 0

    for i < len(text) {
        c := text[i]
        if c == 0x1B {
            start := i
            i += 1
            if i >= len(text) {
                break
            }
            next := text[i]

            if next == '[' {
                i += 1
                for i < len(text) && ((text[i] < 0x40) || (text[i] > 0x7E)) {
                    i += 1
                }
                if i < len(text) {
                    i += 1
                }
                
                append(&escapes, text[start:i])
            } else if next == ']' {
                i += 1
                for i < len(text) {
                    if text[i] == 0x07 {
                        i += 1
                        break;
                    } else if text[i] == 0x1B && i+1 < len(text) && text[i+1] == '\\' {
                        i += 2
                        break
                    }
                    i += 1
                }
                append(&escapes, text[start:i])

            } else if next == 'P' || next == '^' || next == '_' {
                i += 1
                for i < len(text) {
                    if text[i] == 0x1B && i+1 < len(text) && text[i+1] == '\\' {
                        i += 2
                        break
                    }
                    i += 1
                }
                append(&escapes, text[start:i])

            } else {
                i += 1
                append(&escapes, text[start:i])
            }
        } else if c == 0x08 || c == 0x07 {
            start := i
            i += 1
            append(&escapes, text[start:i])
        } else {
            append(&sanitized, c)
            i += 1
        }

    }

    return sanitized, escapes
}

map_glfw_key_to_escape_sequence :: proc(key: i32, mods: i32) -> (ret_val: string, did_allocate: bool = false) {
    ctrl  := mods == CTRL
    alt   := mods == ALT
    shift := mods == SHIFT

    // Ctrl + A-Z → control characters
    if ctrl {
        if key == glfw.KEY_LEFT_BRACKET {
            return "\x1B", false // ESC
        }

        if key == glfw.KEY_GRAVE_ACCENT {
            return "\x00", false // NUL
        }

        if key == glfw.KEY_SLASH && shift {
            return "\x7F", false // DEL
        }

        if key == glfw.KEY_BACKSLASH {
            return "\x1C", false // FS
        }

        if key == glfw.KEY_RIGHT_BRACKET {
            return "\x1D", false // GS
        }
    }
    
    if ctrl && key >= glfw.KEY_A && key <= glfw.KEY_Z {
    	builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        
    	strings.write_rune(&builder, rune(u64(key - glfw.KEY_A + 1)))
        
        ch := strings.to_string(builder)
        
        return strings.clone(ch), true
    }

    switch key {
    case glfw.KEY_ENTER:
        return "\r", false
    case glfw.KEY_BACKSPACE:
        return "\b", false
    case glfw.KEY_TAB:
        if shift {
            return "\x1B[Z", false
        }
        return "\t", false
    case glfw.KEY_ESCAPE:
        return "\x1B", false

    case glfw.KEY_UP:
        return "\x1B[A", false
    case glfw.KEY_DOWN:
        return "\x1B[B", false
    case glfw.KEY_RIGHT:
        return "\x1B[C", false
    case glfw.KEY_LEFT:
        return "\x1B[D", false

    case glfw.KEY_HOME:
        return "\x1B[H", false
    case glfw.KEY_END:
        return "\x1B[F", false
    case glfw.KEY_PAGE_UP:
        return "\x1B[5~", false
    case glfw.KEY_PAGE_DOWN:
        return "\x1B[6~", false
    case glfw.KEY_INSERT:
        return "\x1B[2~", false
    case glfw.KEY_DELETE:
        return "\x1B[3~", false

    case glfw.KEY_F1:
        return "\x1BOP", false
    case glfw.KEY_F2:
        return "\x1BOQ", false
    case glfw.KEY_F3:
        return "\x1BOR", false
    case glfw.KEY_F4:
        return "\x1BOS", false
    case glfw.KEY_F5:
        return "\x1B[15~", false
    case glfw.KEY_F6:
        return "\x1B[17~", false
    case glfw.KEY_F7:
        return "\x1B[18~", false
    case glfw.KEY_F8:
        return "\x1B[19~", false
    case glfw.KEY_F9:
        return "\x1B[20~", false
    case glfw.KEY_F10:
        return "\x1B[21~", false
    case glfw.KEY_F11:
        return "\x1B[23~", false
    case glfw.KEY_F12:
        return "\x1B[24~", false
    }

    // Alt + printable key → ESC + char
    if alt && key >= glfw.KEY_SPACE && key <= glfw.KEY_Z {
    	builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        
    	strings.write_rune(&builder, rune(key))
        
        ch: string = strings.to_string(builder)
        
        if shift {
            ch = strings.to_upper(ch)
        } else {
            ch = strings.to_lower(ch)
        }
        
        return strings.concatenate({ "\x1B", ch }), true
    }

    return "", false
}

// CREDIT: https://github.com/developer-3/fuzzy-odin
fuzzy :: proc(input: string, dictionary: ^[dynamic]string, results: int = 200) -> []string
{
    scores := make(map[int][dynamic]string)
    defer delete(scores)
    max_score := 0
    for word in dictionary {
        score := levenshtein_dp(input, word)
        if score in scores {
            append(&scores[score], word)
        } else {
            scores[score] = make([dynamic]string)
            append(&scores[score], word)
            max_score = max(max_score, score)
        }
    }

    top := make([dynamic]string)
    for i in 0..=max_score {
        if i in scores == false do continue
        words := scores[i]
        
        sort.quick_sort_proc(words[:], proc (a,b:string) -> int {
            return strings.compare(a,b)
        })
        
        append(&top, ..words[:])

        if results != -1 && len(top) > results {
            break
        }
    }

    if results == -1 || results > len(top) do return top[:]
    return top[:results]
}

// Levenshtein distance
// dynamic programming matrix impl
@private
levenshtein_dp :: proc(a, b: string) -> int
{
    mat_position :: proc(i, j: int, mat: ^[]int, m, n: int) -> int
    {
        if min(i, j) == 0 do return max(i, j)
        return mat[(i-1)*n+(j-1)]
    }

    m, n := len(a), len(b)
    mat := make([]int, m*n)

    if m == 0 do return n
    if n == 0 do return m

    for i in 1..=m {
        for j in 1..=n {
            if min(i, j) == 0 {
                mat[i*n+j] = max(i, j)
                continue
            }

            third := mat_position(i - 1, j - 1, &mat, m, n)
            if a[i-1] != b[j-1] do third += 1

            val := min(
                mat_position(i-1, j, &mat, m, n) + 1, 
                mat_position(i, j - 1, &mat, m, n) + 1, 
                third
            )

            mat[(i-1)*n+(j-1)] = val
        }
    }

    return mat[len(mat)-1]
}


expand_env :: proc(path: string, allocator := context.allocator) -> (string, os2.Error) {
    builder: strings.Builder;
    strings.builder_init(&builder, allocator);
    defer strings.builder_destroy(&builder);

    i := 0;
    for i < len(path) {
        if path[i] == '$' {
            start := i;
            i += 1;
            
            if i < len(path) && path[i] == '{' {
                brace_start := i;
                i += 1;
                end := i;
                for end < len(path) && path[end] != '}' do end += 1;
                if end < len(path) {
                    var_name := path[i:end];
                    value := os2.get_env(var_name, allocator);
                    defer delete(value)
                    
                    strings.write_string(&builder, value);
                    i = end + 1;
                } else {
                    strings.write_string(&builder, path[start:brace_start+1]);
                    i = brace_start + 1;
                }
            } else {
                end := i;
                for end < len(path) && ((path[end] >= 'a' && path[end] <= 'z') ||
                                        (path[end] >= 'A' && path[end] <= 'Z') ||
                                        (path[end] >= '0' && path[end] <= '9') ||
                                        path[end] == '_') { end += 1; }
                if end > i {
                    var_name := path[i:end];
                    value := os2.get_env(var_name, allocator);
                    defer delete(value)
                    
                    strings.write_string(&builder, value);
                    i = end;
                } else {
                    strings.write_rune(&builder, '$');
                }
            }
        } else {
            // Copy literal characters
            j := i;
            for j < len(path) && path[j] != '$' do j += 1;
            strings.write_string(&builder, path[i:j]);
            i = j;
        }
    }

    return strings.clone(strings.to_string(builder)), os2.ERROR_NONE;
}

string_replace :: proc(input, search_term, replace_term: string) -> string {
    if len(search_term) == 0 {
        return strings.clone(input)
    }

    count := 0
    pos := 0
    for {
        idx := strings.index(input[pos:], search_term)
        if idx == -1 {
            break
        }
        count += 1
        pos += idx + len(search_term)
    }
    
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    
    pos = 0
    for {
        idx := strings.index(input[pos:], search_term)
        if idx == -1 {
            strings.write_string(&builder, input[pos:])
            break
        }
        
        strings.write_string(&builder, input[pos:pos + idx])
        strings.write_string(&builder, replace_term)
        pos += idx + len(search_term)
    }

    return strings.clone(strings.to_string(builder))
}