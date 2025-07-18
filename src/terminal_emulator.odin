#+private file
package main

import "vendor:glfw"
import "core:fmt"
import "core:math"
import "core:sys/posix"
import "core:os"
import "core:mem"
import "core:thread"
import "core:unicode/utf8"
import "core:sys/linux"
import "core:strings"
import ft "../../alt-odin-freetype"

suppress := true

cursor_row : int
cursor_col : int

scrollback_buffer: [dynamic][dynamic]u8 = {}
scrollback_limit := 1000
scroll_offset := 0

@(private="package")
scroll_terminal_up :: proc(lines: int) {
    scroll_offset = min(scroll_offset + lines, max(0, len(scrollback_buffer) - cell_count_y))
}

@(private="package")
scroll_terminal_down :: proc(lines: int) {
    scroll_offset = max(scroll_offset - lines, 0)
}

cell_count_x: int
cell_count_y: int

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

@(private="package")
resize_terminal :: proc () {

    // Compute actual term height using cells.
    {
        text := math.round_f32(font_base_px * normal_text_scale)

        error := ft.set_pixel_sizes(primary_font, 0, u32(text))
        assert(error == .Ok)
    
        ascender := f32(primary_font.size.metrics.ascender >> 6)
        descender := f32(primary_font.size.metrics.descender >> 6)
        
        char_map := get_char_map(text)
        char := get_char_with_char_map(char_map, text, ' ')
        if char == nil do return
        
        desired_width := (fb_size.x / 100) * width_percentage    
        
        margin = font_base_px * 5
        
        width = max(desired_width, 500)
        height = fb_size.y - margin * 2
        
        cell_width = char.advance.x
        cell_height = ascender - descender
            
        cell_count_x = int(math.round_f32(width / f32(cell_width)))
        cell_count_y = int(math.round_f32(height / f32(cell_height)))
        
        width = f32(cell_width) * f32(cell_count_x)
        height = f32(cell_height) * f32(cell_count_y)
    }
    
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
    } else {
        is_terminal_open = false
        
        input_mode = .COMMAND
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

    start_row := max(0, len(scrollback_buffer) - cell_count_y - scroll_offset)
    end_row := min(len(scrollback_buffer), start_row + cell_count_y)

    for i in start_row..<end_row {
        row := scrollback_buffer[i]
        add_text(
            &text_rect_cache,
            pen,
            TEXT_MAIN,
            text,
            string(row[:]),
            z_index + 1,
            true,
            -1
        )
        pen.y += (ascender - descender)
    }
    
    if input_mode == .TERMINAL {
        cursor_rect := rect{
            x=x_pos + (f32(cursor_col) * cell_width),
            y=margin + (f32(cursor_row) * cell_height),
            width=cell_width,
            height=cell_height
        }
        
        add_rect(
            &rect_cache,
            cursor_rect,
            no_texture,
            TEXT_MAIN,
            vec2{},
            z_index + 2,
        )
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
ensure_scrollback_row :: proc() {
    if cursor_row >= len(scrollback_buffer) {
        row := make([dynamic]u8, cell_count_x)
        resize(&row, cell_count_x)
        for i in 0..<cell_count_x {
            row[i] = 0
        }
        append(&scrollback_buffer, row)

        if len(scrollback_buffer) > scrollback_limit {
            ordered_remove(&scrollback_buffer, 0)
            cursor_row -= 1
        }
    }
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
        
        fmt.println("raw read:", read_buf[:n])
        
        sanitized, escapes := sanitize_ansi_string(string(read_buf[:n]))
        
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
            case:
                fmt.println(transmute([]u8)escape)
            }
        }
    
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