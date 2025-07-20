#+private file
package main

import "vendor:glfw"
import "core:fmt"
import "core:math"
import "core:sys/posix"
import "core:os"
import "core:mem"
import "core:thread"
import "core:strconv"
import "core:unicode/utf8"
import "core:sys/linux"
import "core:strings"
import ft "../../alt-odin-freetype"

suppress := true

cursor_row : int
cursor_col : int

stored_cursor_col : int = 0
stored_cursor_row : int = 0

scrollback_buffer := make([dynamic][dynamic]rune)
scrollback_limit := 1000
scroll_offset := 0

cell_count_x: int
cell_count_y: int

terminal_title : string

@(private="package")
is_terminal_open := false

TtyHandle :: struct {
    pid: int,
    master_fd: posix.FD, // posix
    h_input: uintptr, // windows
    h_output: uintptr, // windows
}

tty : ^TtyHandle = nil
input_accumulator : [dynamic]u8 = {}

width_percentage : f32 = 20
x_pos : f32 = 0

width : f32
height : f32
margin : f32

border_color : vec4

cell_width : f32
cell_height : f32

Ansi_State :: enum {
    Normal,
    Esc,
    Csi,
    Osc,
}

ansi_state := Ansi_State.Normal
ansi_buf   : [dynamic]u8
alt_buffer: [dynamic][dynamic]rune
using_alt_buffer := false
cursor_visible := true
scroll_top := 0
scroll_bottom : int

@(private="package")
scroll_terminal_up :: proc(lines: int) {
    scroll_offset = min(scroll_offset + lines, max(0, len(scrollback_buffer) - cell_count_y))
}

@(private="package")
scroll_terminal_down :: proc(lines: int) {
    scroll_offset = max(scroll_offset - lines, 0)
}

when ODIN_OS == .Linux {
    TIOCSCTTY: u64 = 0x540E
    TCSANOW: int = 0
    
    spawn_shell :: proc() {
        cwd_string := strings.clone_to_cstring(cwd)
        
        posix.chdir(cwd_string)
        
        delete(cwd_string)
        
        master_fd := posix.posix_openpt({
            posix.O_Flag_Bits.RDWR, 
            posix.O_Flag_Bits.NOCTTY,
        })
        
        if master_fd < 0 {
            panic("Failed to open PTY master")
        }
        
        posix.grantpt(master_fd)
        posix.unlockpt(master_fd)
    
        slave_name := posix.ptsname(master_fd)
    
        pid := posix.fork()
        if pid == 0 {
            posix.setsid()
            slave_fd := posix.open(slave_name, {posix.O_Flag_Bits.RDWR})
        
            linux.ioctl(linux.Fd(slave_fd), u32(TIOCSCTTY), 0)
            posix.setpgid(0, 0) // set child as its own process group leader
            posix.tcsetpgrp(slave_fd, posix.getpgrp()) // set foreground pgrp

            posix.dup2(slave_fd, 0) // stdin
            posix.dup2(slave_fd, 1) // stdout
            posix.dup2(slave_fd, 2) // stderr
        
            termios := posix.termios{}
            _ = posix.tcgetattr(slave_fd, &termios)
            termios.c_lflag |= {.ICANON, .ECHO, .ECHOE, .ECHOK, .ECHONL}
            termios.c_cc[posix.Control_Char.VERASE] = 0x7f
            //termios.c_lflag &= ~{.ICANON}
            
            err := posix.tcsetattr(slave_fd, posix.TC_Optional_Action.TCSANOW, &termios)
            assert(err == posix.result.OK)

            posix.close(master_fd)
            posix.setenv("TERM", "xterm", true)
            
            posix.execl("/bin/bash", "bash", nil)
            
            posix._exit(1)
        }
        
        tty = new(TtyHandle)
        tty^ = TtyHandle{int(pid), master_fd, 0, 0}
        
        terminal_title = "Terminal"
        init_terminal_thread()
    }
    
    write_to_shell :: proc(h: TtyHandle, data: string) {
        count := posix.write(h.master_fd, raw_data(data), len(data))
        
        if count != len(data) {
            err_code := posix.errno()
            fmt.println(err_code)
        }
    }
    
    read_from_shell :: proc(h: TtyHandle, buf: []u8) -> int {
        return posix.read(h.master_fd, raw_data(buf), len(buf))
    }
    
    close_shell :: proc(h: TtyHandle) {
        posix.kill(posix.pid_t(h.pid), posix.Signal.SIGKILL)
        posix.close(h.master_fd)
    }
} else when ODIN_OS == .Windows {
    spawn_shell :: proc() {
        panic("canont spawn shell yet on windows")
    }
}

@(private="package")
resize_terminal :: proc () {
    text := math.round_f32(font_base_px * normal_text_scale)

    error := ft.set_pixel_sizes(primary_font, 0, u32(text))
    assert(error == .Ok)

    ascender := f32(primary_font.size.metrics.ascender >> 6)
    descender := f32(primary_font.size.metrics.descender >> 6)
    
    char_map := get_char_map(text)
    char := get_char_with_char_map(char_map, text, ' ')
    if char == nil do return
    
    desired_width := (fb_size.x / 100) * width_percentage    
    
    margin = font_base_px * 6
    
    width = max(desired_width, input_mode == .TERMINAL ? fb_size.x-300 : 500)
    height = fb_size.y - margin * 2
    
    cell_width = char.advance.x
    cell_height = ascender - descender
    
    cell_count_x = int(math.round_f32(width / f32(cell_width)))
    cell_count_y = int(math.round_f32(height / f32(cell_height)))
    
    width = f32(cell_width) * f32(cell_count_x)
    height = f32(cell_height) * f32(cell_count_y)
    
    clear(&scrollback_buffer)
    resize(&scrollback_buffer, cell_count_y)
    
    for &row in scrollback_buffer {
        resize(&row, cell_count_x)
    }
    
    scroll_bottom = cell_count_y - 1
}

@(private="package")
toggle_terminal_emulator :: proc() {
    if is_terminal_open == false {
        suppress = false
        is_terminal_open = true
        
        input_mode = .TERMINAL
        
        if tty == nil {
            spawn_shell()
        }
        
        resize_terminal()
    } else {
        is_terminal_open = false
        
        input_mode = .COMMAND
        
        resize_terminal()
    }
}

@(private="package")
draw_terminal_emulator :: proc() {
    if suppress {
        x_pos = fb_size.x
        return
    }

    text := math.round_f32(font_base_px * normal_text_scale)
    error := ft.set_pixel_sizes(primary_font, 0, u32(text))
    assert(error == .Ok)

    ascender := f32(primary_font.size.metrics.ascender >> 6)
    descender := f32(primary_font.size.metrics.descender >> 6)
    line_thickness := math.round_f32(font_base_px * line_thickness_em)

    small_text := math.round_f32(font_base_px * small_text_scale)
    padding := small_text
    
    z_index: f32 = 100
    reset_rect_cache(&rect_cache)
    reset_rect_cache(&text_rect_cache)
    
    {
        bg_rect := rect{
            x_pos - padding,
            margin - padding, 
            width + padding * 2, 
            height + padding * 2,
        }
        
        add_rect(&rect_cache, bg_rect, no_texture, BG_MAIN_10, vec2{}, z_index)

        border_rect := rect{
            bg_rect.x - line_thickness,
            bg_rect.y - line_thickness,
            bg_rect.width + line_thickness * 2,
            bg_rect.height + line_thickness * 2,
        }
        
        add_rect(&rect_cache, border_rect, no_texture, border_color, vec2{}, z_index - 1)
    }

    pen := vec2{x_pos, margin}
    
    // Draw Terminal Title
    {
        title_pos := vec2{
            x_pos,
            font_base_px * 5,
        }
        
        add_text(
            &text_rect_cache,
            title_pos,
            TEXT_MAIN,
            text,
            terminal_title,
            z_index + 1,
            true,
            -1
        )

    }

    start_row := max(0, len(scrollback_buffer) - cell_count_y - scroll_offset)
    end_row := min(len(scrollback_buffer), start_row + cell_count_y)

    for i in start_row..<end_row {
        row := scrollback_buffer[i]
        
        str := utf8.runes_to_string(row[:])
        defer delete(str)
        
        add_text(
            &text_rect_cache,
            pen,
            TEXT_MAIN,
            text,
            str,
            z_index + 1,
            true,
            -1
        )
        pen.y += (ascender - descender)
    }
    
    if input_mode == .TERMINAL {
        cursor_rect := rect{
            x=x_pos + (f32(cursor_col) * cell_width),
            y=margin + (f32(cursor_row - start_row) * cell_height),
            width=cell_width,
            height=cell_height
        }
        
        if cursor_rect.y + cursor_rect.height < ((margin + padding) + height) {
            add_rect(
                &rect_cache,
                cursor_rect,
                no_texture,
                TEXT_MAIN,
                vec2{},
                z_index + 2,
            )
        }
    }

    draw_rects(&text_rect_cache)
    draw_rects(&rect_cache)
}

@(private="package")
handle_terminal_emulator_input :: proc(key, scancode, action, mods: i32) -> (do_continue: bool) {
    if action == glfw.RELEASE do return
    
    if key == (glfw.KEY_D) {
        if mods == CTRL {
            input_mode = .COMMAND
            return false
        }
    }
    
    seq, did_allocate := map_glfw_key_to_escape_sequence(key, mods)
    
    if seq != "" {
        write_to_shell(tty^, seq)
    }
    
    if did_allocate {
        delete(seq)
    }
    
    return true
}

@(private="package")
tick_terminal_emulator :: proc() {
    if suppress {
        return
    }
    
    small_text := math.round_f32(font_base_px * small_text_scale)

    if input_mode == .TERMINAL {
        border_color = smooth_lerp_vec4(border_color, BG_MAIN_40, 30, frame_time)
    } else {
        border_color = smooth_lerp_vec4(border_color, BG_MAIN_20, 30, frame_time)
    }
    
    if is_terminal_open {
        x_pos = smooth_lerp(x_pos, fb_size.x - width - font_base_px - small_text, 100, frame_time)
    } else {
        x_pos = smooth_lerp(x_pos, fb_size.x, 100, frame_time)
        
        if int(x_pos) > int(fb_size.x - 5) {
            suppress = true
        }
    }
}

@(private="package")
ensure_scrollback_row :: proc() {
    if cursor_row >= len(scrollback_buffer) {
        row := make([dynamic]rune, cell_count_x)
        
        append(&scrollback_buffer, row)

        if len(scrollback_buffer) > scrollback_limit {
            ordered_remove(&scrollback_buffer, 0)
            cursor_row -= 1
            
            fmt.println(cursor_row)
        }
        
        scroll_terminal_down(2)
    }
}

@(private="package")
handle_terminal_input :: proc(key: rune) {
    if tty == nil do return
    
    bytes, len := utf8.encode_rune(key)
    
    append(&input_accumulator, ..bytes[:len])

    cmd := string(input_accumulator[:])
    write_to_shell(tty^, cmd)
 
    clear(&input_accumulator)
}


@(private="package")
terminal_loop :: proc(thread: ^thread.Thread) {
    for !glfw.WindowShouldClose(window) {
        if tty == nil do continue
    
        read_buf := make([dynamic]u8, 1024)
        defer delete(read_buf)
    
        n := posix.read(tty.master_fd, raw_data(read_buf), len(read_buf))
        
        if n == -1 {
            clear(&scrollback_buffer)
            close_shell(tty^)
            toggle_terminal_emulator()
            tty = nil
            return
        }
        
        process_ansi_chunk(string(read_buf[:n]))
        
        /*
        sanitized, escapes := sanitize_ansi_string(string(read_buf[:n]))
        
        /*
        for escape in escapes {
            switch escape {
            case "\x07":
                break
            case "\x1B[H":
                cursor_row = 0
                cursor_col = 0
            case "\x1B[2J":
                cursor_row = 0
                cursor_col = 0
                clear(&scrollback_buffer)
            case "\x1B[0J":
                clear(&scrollback_buffer)
            case "\x1B[3J":
                clear(&scrollback_buffer)
            case "\x1B[K":
                for i in cursor_col..<cell_count_x {
                    scrollback_buffer[cursor_row][i] = 0
                }
            case "\x1B[1K":
                for i in 0..<cursor_col+1 {
                    scrollback_buffer[cursor_row][i] = 0
                }
            case "\x1B[2K":
                for i in 0..<cell_count_x {
                    scrollback_buffer[cursor_row][i] = 0
                }
            case "\b", "\x7F":
                if cursor_col > 0 {
                    cursor_col -= 1
                    scrollback_buffer[cursor_row][cursor_col] = 0
                } else if cursor_row > 0 {
                    cursor_row -= 1
                    cursor_col = cell_count_x - 1
                    scrollback_buffer[cursor_row][cursor_col] = 0
                }
                break
            case "\x1b7":
                stored_cursor_col = cursor_col
                stored_cursor_row = cursor_row
            case "\x1b8":
                cursor_col = stored_cursor_col
                cursor_row = stored_cursor_row
            case:
                fmt.println(transmute([]u8)escape)
            }
        }
        */
    
        for char in sanitized {
            switch char {
            case '\r':
                cursor_col = 0
                continue
            case '\n':
                cursor_row += 1
                
                if cursor_row >= len(scrollback_buffer) {
                    ensure_scrollback_row()
                    cursor_row = len(scrollback_buffer) - 1
                }
                
                cursor_col = 0
                
                continue
            case '\t':
                for i in 0..<8 {
                    cursor_col = clamp(cursor_col + 1, 0, len(scrollback_buffer))
                }
                
                continue
            }
            if cursor_row >= len(scrollback_buffer) {
                ensure_scrollback_row()
                cursor_row = len(scrollback_buffer) - 1
            }
    
            if cursor_col >= cell_count_x {
                cursor_col = 0
                cursor_row += 1
                if cursor_row >= len(scrollback_buffer) {
                    ensure_scrollback_row()
                    cursor_row = len(scrollback_buffer) - 1
                }
            }
    
            scrollback_buffer[cursor_row][cursor_col] = char
            cursor_col += 1
        }
        
        */
    }
}

/*
Ansi_State :: enum{
    Normal,
    Esc,
    Csi,
    Osc,
}

ansi_state := Ansi_State.Normal

ansi_buf : [dynamic]u8

process_ansi_chunk :: proc(input: string) {
    for i := 0; i < len(input); i += 1 {
        b := input[i]

        switch ansi_state {
        // --------------------------------------------------------
        case .Normal:
            if b == 0x1B { // ESC
                ansi_state = .Esc
                clear(&ansi_buf)
                append(&ansi_buf, b)
                continue
            }
            
            if b == 0x08 { // Backspace
                if cursor_col > 0 {
                    cursor_col -= 1
                    scrollback_buffer[cursor_row][cursor_col] = 0
                } else if cursor_row > 0 {
                    cursor_row -= 1
                    cursor_col = cell_count_x - 1
                    scrollback_buffer[cursor_row][cursor_col] = 0
                }
                return
            }
        
            if b == 0x07 { // BEL
                return
            }
        
            if b == '\n' {
                cursor_row += 1
                ensure_scrollback_row()
                cursor_col = 0
                return
            }
        
            if b == '\r' {
                cursor_col = 0
                return
            }
            
            r := utf8.rune_at(input, i)
            size := utf8.rune_size(r)
            
            handle_normal_char(r)
            
            // -1 because for loop
            i += size-1
            continue

        // --------------------------------------------------------
        case .Esc:
            append(&ansi_buf, b)
            if b == '[' {
                ansi_state = .Csi
                continue
            } else if b == ']' {
                ansi_state = .Osc
                continue
            } else {
                handle_simple_escape(ansi_buf[:])
                ansi_state = .Normal
            }

        // --------------------------------------------------------
        case .Csi:
            append(&ansi_buf, b)
            if b >= 0x40 && b <= 0x7E {
                handle_csi_seq(string(ansi_buf[:]))
                ansi_state = .Normal
            }

        // --------------------------------------------------------
        case .Osc:
            append(&ansi_buf, b)
            if b == 0x07 { // BEL terminator
                handle_osc_seq(string(ansi_buf[:]))
                ansi_state = .Normal
            } else if b == 0x1B && i+1 < len(input) && input[i+1] == '\\' {
                append(&ansi_buf, input[i+1])
                i += 1
                handle_osc_seq(string(ansi_buf[:]))
                ansi_state = .Normal
            }
        }
    }
}

handle_simple_escape :: proc(seq: []u8) {
    // seq includes ESC + one byte
    if len(seq) < 2 {
        return
    }

    switch seq[1] {
    case '7': // Save cursor
        stored_cursor_row = cursor_row
        stored_cursor_col = cursor_col
    case '8': // Restore cursor
        cursor_row = stored_cursor_row
        cursor_col = stored_cursor_col
    case '=':
        // Application Keypad Mode Enable (optional)
    case '>':
        // Normal Keypad Mode Enable (optional)
    case:
        // fmt.println("Unhandled simple ESC sequence: ", string(seq))
    }
}


handle_osc_seq :: proc(seq: string) {
    // Strip leading ESC ]
    if len(seq) < 3 { return }
    body := seq[2:] // after ESC ]
    // Trim final BEL or ESC \
    if body[len(body)-1] == 0x07 {
        body = body[:len(body)-1]
    } else if len(body) >= 2 && body[len(body)-2:] == "\x1B\\" {
        body = body[:len(body)-2]
    }

    // OSC format: "number;data"
    parts := strings.split(body, ";")
    defer delete(parts)
    if len(parts) < 2 { return }
    code := parts[0]
    data := parts[1]

    switch code {
    case "0", "2": // Set window title
        // TODO: add this
        // set_window_title(data)
    case:
    }
}

handle_normal_char :: proc(r: rune) {
    if cursor_row >= len(scrollback_buffer) {
        ensure_scrollback_row()
        cursor_row = len(scrollback_buffer) - 1
    }

    if cursor_col >= len(scrollback_buffer[0]) {
        cursor_col = 0
        cursor_row += 1
        if cursor_row >= len(scrollback_buffer) {
            ensure_scrollback_row()
            cursor_row = len(scrollback_buffer) - 1
        }
    }

    scrollback_buffer[cursor_row][cursor_col] = r
    cursor_col += 1
}


handle_csi_seq :: proc(seq: string) {
    // seq includes ESC [ ... final
    if len(seq) < 2 { return }

    final := seq[len(seq)-1]
    params_str := ""
    if len(seq) > 2 {
        params_str = seq[2:len(seq)-1] // everything between '[' and final
    }

    params := parse_csi_params(params_str)

    switch final {
    case 'H', 'f':
        row := len(params) >= 1 && params[0] > 0 ? params[0] - 1 : 0
        col := len(params) >= 2 && params[1] > 0 ? params[1] - 1 : 0
        cursor_row = clamp(row, 0, cell_count_y - 1)
        cursor_col = clamp(col, 0, cell_count_x - 1)

    case 'A':
        delta := len(params) > 0 ? params[0] : 1
        cursor_row = clamp(cursor_row - delta, 0, cell_count_y - 1)

    case 'B':
        delta := len(params) > 0 ? params[0] : 1
        cursor_row = clamp(cursor_row + delta, 0, cell_count_y - 1)

    case 'C':
        delta := len(params) > 0 ? params[0] : 1
        cursor_col = clamp(cursor_col + delta, 0, cell_count_x - 1)

    case 'D':
        delta := len(params) > 0 ? params[0] : 1
        cursor_col = clamp(cursor_col - delta, 0, cell_count_x - 1)

    case 'J':
        erase_screen(params)

    case 'K':
        fmt.println("erasing entire line")
        erase_line(params)

    case 'm': // SGR (colors, bold, etc.)
        set_graphics_rendition(params)

    case:
    }
}

parse_csi_params :: proc(s: string) -> [dynamic]int {
    params: [dynamic]int = nil
    parts := strings.split(s, ";")
    for p in parts {
        if len(p) == 0 {
            append(&params, 0)
        } else {
            val, ok := strconv.parse_int(p, 10)
            append(&params, ok ? int(val) : 0)
        }
    }
    return params
}

erase_screen :: proc(params: [dynamic]int) {
    mode := len(params) > 0 ? params[0] : 0

    switch mode {
    case 0:
        for r in cursor_row..<len(scrollback_buffer) {
            start_col := r == cursor_row ? cursor_col : 0
            for c in start_col..<len(scrollback_buffer[cursor_row]) {
                scrollback_buffer[r][c] = 0
            }
        }
    case 1:
        for r in 0..=cursor_row {
            end_col := r == cursor_row ? cursor_col : cell_count_x - 1
            for c in 0..=end_col {
                scrollback_buffer[r][c] = 0
            }
            
            fmt.println(scrollback_buffer[r])
        }
    case 2:
        for &row in scrollback_buffer {
            clear(&row)
            resize(&row, len(scrollback_buffer))
        }
        
        scroll_offset = 0

        resize_terminal()
    }
}

set_graphics_rendition :: proc(params: [dynamic]int) {
    // TODO: Implement colors/bold/etc. if needed
}
*/

erase_line :: proc(params: [dynamic]int) {
    mode := len(params) > 0 ? params[0] : 0
    switch mode {
    case 0:
        for c in cursor_col..<cell_count_x {
            scrollback_buffer[cursor_row][c] = 0
        }
    case 1:
        for c in 0..=cursor_col {
            scrollback_buffer[cursor_row][c] = 0
        }
    case 2:
        for c in 0..<cell_count_x {
            scrollback_buffer[cursor_row][c] = 0
        }
    }
}

erase_screen :: proc(params: [dynamic]int) {
    mode := len(params) > 0 ? params[0] : 0

    switch mode {
    case 0:
        for r in cursor_row..<cell_count_y {
            start_col := r == cursor_row ? cursor_col : 0
            for c in start_col..<cell_count_x {
                scrollback_buffer[r][c] = 0
            }
        }
    case 1:
        for r in 0..=cursor_row {
            end_col := r == cursor_row ? cursor_col : cell_count_x - 1
            for c in 0..=end_col {
                scrollback_buffer[r][c] = 0
            }
            
        }
    case 2:
        for &row in scrollback_buffer {
            for &char in row {
                (&char)^ = 0
            }
        }
        
        scroll_offset = 0
    }
}

parse_csi_params :: proc(s: string) -> [dynamic]int {
    params: [dynamic]int = nil
    parts := strings.split(s, ";")
    for p in parts {
        if len(p) == 0 {
            append(&params, 0)
        } else {
            val, ok := strconv.parse_int(p, 10)
            append(&params, ok ? int(val) : 0)
        }
    }
    return params
}
process_ansi_chunk :: proc(input: string) {
    for i := 0; i < len(input); i += 1 {
        b := input[i]

        switch ansi_state {
        case .Normal:
            if b == 0x1B { // esc key
                ansi_state = .Esc
                clear(&ansi_buf)
                append(&ansi_buf, b)
                continue
            }

            if b == 0x08 { // backk spacuhhh
                if cursor_col > 0 {
                    cursor_col -= 1
                    scrollback_buffer[cursor_row][cursor_col] = 0
                } else if cursor_row > 0 {
                    cursor_row -= 1
                    cursor_col = cell_count_x - 1
                    scrollback_buffer[cursor_row][cursor_col] = 0
                }
                return
            }

            if b == 0x07 { // bell
                continue
            }

            if b == 0x0A {
                newline()
                continue
            }

            if b == 0x0D {
                cursor_col = 0
                continue
            }
            
            if b < 0x20 {
                continue
            }

            r := utf8.rune_at(input, i)
            size := utf8.rune_size(r)
            handle_normal_char(r)
            i += size - 1
            
            continue

        case .Esc:
            append(&ansi_buf, b)
            if b == '[' {
                ansi_state = .Csi
                continue
            } else if b == ']' {
                ansi_state = .Osc
                continue
            } else {
                handle_simple_escape(ansi_buf[:])
                ansi_state = .Normal
            }

        case .Csi:
            append(&ansi_buf, b)
            if b >= 0x40 && b <= 0x7E {
                handle_csi_seq(string(ansi_buf[:]))
                ansi_state = .Normal
            }

        case .Osc:
            append(&ansi_buf, b)
            if b == 0x07 { // BEL terminator
                handle_osc_seq(string(ansi_buf[:]))
                ansi_state = .Normal
            } else if b == 0x1B && i + 1 < len(input) && input[i+1] == '\\' {
                append(&ansi_buf, input[i+1])
                i += 1
                handle_osc_seq(string(ansi_buf[:]))
                ansi_state = .Normal
            }
        }
    }
}

newline :: proc() {
    cursor_row += 1
    if cursor_row > scroll_bottom {
        scroll_region_up()
        cursor_row = scroll_bottom
    }
    cursor_col = 0
    
}


scroll_region_up :: proc() {
    for r in scroll_top..<scroll_bottom {
        if r < scroll_bottom {
            clear(&scrollback_buffer[r])
            append(&scrollback_buffer[r], ..scrollback_buffer[r+1][:])
        } else {
            clear(&scrollback_buffer[r])
            resize(&scrollback_buffer[r], cell_count_x)
        }
    }
}

handle_simple_escape :: proc(seq: []u8) {
    if len(seq) < 2 { return }
    switch seq[1] {
    case '7':
        stored_cursor_row = cursor_row
        stored_cursor_col = cursor_col
    case '8':
        cursor_row = stored_cursor_row
        cursor_col = stored_cursor_col
    case '=': // application Keypad Mode Enable
    case '>': // normal Keypad Mode Enable
    case 'c': // full reset (RIS)
        reset_terminal()
    }
}

reset_terminal :: proc() {
    fmt.println("WARN: RESET TERMINAL NOT POSSIBLE")
}

sanitize_title :: proc(s: string) -> [dynamic]rune {
    result := make([dynamic]rune)
    
    for b in s {
        if b >= 0x20 || b == '\t' {
            append(&result, b)
        }
    }
    return result
}

handle_osc_seq :: proc(seq: string) {
    if len(seq) < 3 { return }
    body := seq[2:]
    if body[len(body)-1] == 0x07 {
        body = body[:len(body)-1]
    } else if len(body) >= 2 && body[len(body)-2:] == "\x1B\\" {
        body = body[:len(body)-2]
    }

    parts := strings.split(body, ";")
    defer delete(parts)
    if len(parts) < 2 { return }
    code := parts[0]
    data := parts[1]
    switch code {
    case "0", "2":
        sanitized := sanitize_title(data)
        
        terminal_title = utf8.runes_to_string(sanitized[:])
        
        delete(sanitized)
    }
}

handle_normal_char :: proc(r: rune) {
    if cursor_row >= len(scrollback_buffer) {
        ensure_scrollback_row()
        cursor_row = len(scrollback_buffer) - 1
    }

    if cursor_col >= cell_count_x {
        cursor_col = 0
        newline()
    }

    scrollback_buffer[cursor_row][cursor_col] = r
    cursor_col += 1
}

handle_csi_seq :: proc(seq: string) {
    if len(seq) < 2 { return }

    final := seq[len(seq)-1]
    params_str := len(seq) > 2 ? seq[2:len(seq)-1] : ""
    params := parse_csi_params(params_str)

    switch final {
    case 'H', 'f':
        row := len(params) >= 1 && params[0] > 0 ? params[0] - 1 : 0
        col := len(params) >= 2 && params[1] > 0 ? params[1] - 1 : 0
        cursor_row = clamp(row, 0, cell_count_y - 1)
        
        cursor_col = clamp(col, 0, cell_count_x - 1)

    case 'A':
        delta := len(params) > 0 ? params[0] : 1
        cursor_row = clamp(cursor_row - delta, 0, cell_count_y - 1)

    case 'B':
        delta := len(params) > 0 ? params[0] : 1
        cursor_row = clamp(cursor_row + delta, 0, cell_count_y - 1)

    case 'C':
        delta := len(params) > 0 ? params[0] : 1
        cursor_col = clamp(cursor_col + delta, 0, cell_count_x - 1)

    case 'D':
        delta := len(params) > 0 ? params[0] : 1
        cursor_col = clamp(cursor_col - delta, 0, cell_count_x - 1)

    case 'E':
        delta := len(params) > 0 ? params[0] : 1
        cursor_row = clamp(cursor_row + delta, 0, cell_count_y - 1)
        
        cursor_col = 0

    case 'F':
        delta := len(params) > 0 ? params[0] : 1
        cursor_row = clamp(cursor_row - delta, 0, cell_count_y - 1)
        
        cursor_col = 0

    case 'G':
        col := len(params) > 0 ? params[0] - 1 : 0
        cursor_col = clamp(col, 0, cell_count_x - 1)

    case 'J':
        erase_screen(params)

    case 'K':
        erase_line(params)

    case 'L':
        insert_lines(len(params) > 0 ? params[0] : 1)

    case 'M':
        delete_lines(len(params) > 0 ? params[0] : 1)

    case 'P':
        delete_chars(len(params) > 0 ? params[0] : 1)

    case '@':
        insert_chars(len(params) > 0 ? params[0] : 1)

    case 'm':
        set_graphics_rendition(params)

    case 'r':
        set_scroll_region(params)

    case 's':
        stored_cursor_row = cursor_row
        stored_cursor_col = cursor_col

    case 'u':
        cursor_row = stored_cursor_row
        cursor_col = stored_cursor_col

    case 'c':
        // respond("\x1b[?1;0c") // "VT100"

    case '?':
        handle_private_mode(seq)
    }
}

handle_private_mode :: proc(seq: string) {
    if strings.contains(seq, "?1049h") {
        enable_alt_buffer()
    } else if strings.contains(seq, "?1049l") {
        disable_alt_buffer()
    } else if strings.contains(seq, "?25l") {
        cursor_visible = false
    } else if strings.contains(seq, "?25h") {
        cursor_visible = true
    }
}

set_scroll_region :: proc(params: [dynamic]int) {
    t := len(params) > 0 ? params[0] - 1 : 0
    b := len(params) > 1 ? params[1] - 1 : cell_count_y - 1
    scroll_top = clamp(t, 0, cell_count_y - 1)
    scroll_bottom = clamp(b, scroll_top, cell_count_y - 1)
    cursor_row = scroll_top
}

insert_lines :: proc(n: int) { }
delete_lines :: proc(n: int) { }
insert_chars :: proc(n: int) { }
delete_chars :: proc(n: int) { }

enable_alt_buffer :: proc() {
    resize(&alt_buffer, len(scrollback_buffer))
    for i in 0..<len(scrollback_buffer) {
        alt_buffer[i] = make([dynamic]rune, cell_count_x)
        for j in 0..<cell_count_x {
            alt_buffer[i][j] = scrollback_buffer[i][j]
        }
    }
    clear(&scrollback_buffer)
    using_alt_buffer = true
}

disable_alt_buffer :: proc() {
    clear(&scrollback_buffer)
    resize(&scrollback_buffer, len(alt_buffer))
    for i in 0..<len(alt_buffer) {
        scrollback_buffer[i] = make([dynamic]rune, cell_count_x)
        for j in 0..<cell_count_x {
            scrollback_buffer[i][j] = alt_buffer[i][j]
        }
    }
    using_alt_buffer = false
}

set_graphics_rendition :: proc(params: [dynamic]int) {
}
