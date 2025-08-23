/*
    I WOULD JUST LIKE TO STATE.
    This terminal emulator is very bad.
    It can *barely* *almost* run some TUI apps.
    It's probably not compliant, or secure.
    I don't understand terminals.
    
    These archaic standards from when germany was still in twain...

    Please rewrite this to be good.
    Thank you.
*/

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
import "core:sync"
import "core:time"
import ft "../../alt-odin-freetype"
import "base:runtime"

suppress := true


scrollback_limit := 1000

cell_count_x: int
cell_count_y: int

@(private="package")
is_terminal_open := false

TtyHandle :: struct {
    pid : int,
    master_fd : posix.FD, // posix
    h_input : uintptr, // windows
    h_output : uintptr, // windows
    
    scrollback_buffer : [dynamic][dynamic]rune,
    alt_buffer : [dynamic][dynamic]rune,
    
    cursor_row : int,
    cursor_col : int,
    
    stored_cursor_col : int,
    stored_cursor_row : int,
    
    using_alt_buffer : bool,
    scroll_top : int,
    scroll_bottom : int,
    
    title: string,
}

terminal_mutex : sync.Mutex

current_terminal_idx : int
terminals : [10]^TtyHandle = {}

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

cursor_visible := true

@(private="package")
scroll_terminal_up :: proc(lines: int, index: int = current_terminal_idx) {
}

@(private="package")
scroll_terminal_down :: proc(lines: int, index: int = current_terminal_idx) {
}

when ODIN_OS == .Linux {
    TIOCSCTTY: u64 = 0x540E
    TCSANOW: int = 0
    
    save_parent_termios :: proc() -> posix.termios {
        termios := posix.termios{}
        err := posix.tcgetattr(0, &termios)
        if err != posix.result.OK {
            fmt.println("Failed to save parent termios")
        }
        
        fmt.println("saved parent")
        return termios
    }
    
    restore_parent_termios :: proc(termios: ^posix.termios) {
        err := posix.tcsetattr(0, posix.TC_Optional_Action.TCSANOW, termios)
        if err != posix.result.OK {
            fmt.println("Failed to restore parent termios")
        }
        
        fmt.println("restored parent")
    }
    
    cleanup_tty :: proc(tty: TtyHandle) {
        posix.close(tty.master_fd)
        posix.waitpid(posix.pid_t(tty.pid), nil, {})
        
        delete(tty.scrollback_buffer)
        delete(tty.alt_buffer)
        delete(tty.title)
    }
    
    spawn_shell :: proc() -> TtyHandle {
        fmt.println("Spawning shell..")
    
        parent_termios := save_parent_termios()
    
        cwd_string := strings.clone_to_cstring(cwd)
        posix.chdir(cwd_string)
        delete(cwd_string)
    
        master_fd := posix.posix_openpt({posix.O_Flag_Bits.RDWR, posix.O_Flag_Bits.NOCTTY})
        if master_fd < 3 {
            restore_parent_termios(&parent_termios)
            panic("Failed to open PTY master")
        }
    
        flags := posix.fcntl(master_fd, posix.FCNTL_Cmd.GETFL, 0)
        posix.fcntl(master_fd, posix.FCNTL_Cmd.SETFL, flags | posix.O_NONBLOCK)
    
        posix.grantpt(master_fd)
        posix.unlockpt(master_fd)
    
        slave_name := posix.ptsname(master_fd)
    
        pid := posix.fork()
        if pid == 0 {
            posix.setsid()
            slave_fd := posix.open(slave_name, {posix.O_Flag_Bits.RDWR})
    
            linux.ioctl(linux.Fd(slave_fd), u32(TIOCSCTTY), 0)
            posix.setpgid(0, 0)
            posix.tcsetpgrp(slave_fd, posix.getpgrp())
    
            posix.dup2(slave_fd, 0) // stdin
            posix.dup2(slave_fd, 1) // stdout
            posix.dup2(slave_fd, 2) // stderr
    
            termios := posix.termios{}
            _ = posix.tcgetattr(slave_fd, &termios)
            termios.c_lflag |= {.ICANON, .ECHO, .ECHOE, .ECHOK, .ECHONL}
            termios.c_cc[posix.Control_Char.VERASE] = 0x7f
    
            err := posix.tcsetattr(slave_fd, posix.TC_Optional_Action.TCSANOW, &termios)
            assert(err == posix.result.OK)
    
            posix.close(master_fd)
            posix.close(slave_fd) // Close slave_fd in child after dup2
            posix.setenv("TERM", "xterm", true)
    
            posix.execl("/bin/bash", "bash", nil)
            posix._exit(1)
        }
    
        // Ensure parent’s stdin/stdout/stderr are not tied to PTY
        posix.dup2(0, 0)
        posix.dup2(1, 1)
        posix.dup2(2, 2)
    
        // Restore parent’s terminal settings
        restore_parent_termios(&parent_termios)
    
        tty := TtyHandle{
            int(pid),
            master_fd,
            0,
            0,
            make([dynamic][dynamic]rune),
            make([dynamic][dynamic]rune),
            0,
            0,
            0,
            0,
            false,
            0,
            0,
            "Terminal",
        }
    
        init_terminal_thread()
    
        return tty
    }
    
    write_to_shell :: proc(h: TtyHandle, data: string) {
        count := posix.write(h.master_fd, raw_data(data), len(data))
        
        if count != len(data) {
            err_code := posix.errno()
            fmt.println("Failed to write to shell, posix err: ", err_code)
        }
    }
    
    read_from_shell :: proc(h: TtyHandle, buf: []u8) -> int {
        return posix.read(h.master_fd, raw_data(buf), len(buf))
    }
    
} 

when ODIN_OS == .Windows {
    cleanup_tty :: proc(tty: TtyHandle) {
    }
    
    spawn_shell :: proc() -> TtyHandle {
        fmt.println("Windows can't do TTY yet!")
        
        tty := TtyHandle{}
    
        return tty
    }
    
    write_to_shell :: proc(h: TtyHandle, data: string) {
    }
    
    read_from_shell :: proc(h: TtyHandle, buf: []u8) -> int {
        return 0
    }
}

@(private="package")
resize_terminal :: proc (index: int = current_terminal_idx) {
    text := math.round_f32(font_base_px * normal_text_scale)

    error := ft.set_pixel_sizes(primary_font, 0, u32(text))
    assert(error == .Ok)

    ascender := f32(primary_font.size.metrics.ascender >> 6)
    descender := f32(primary_font.size.metrics.descender >> 6)
    
    char_map := get_char_map(text)
    char := get_char_with_char_map(char_map, text, ' ')
    if char == nil do return
    
    margin = font_base_px * 6
    
    width = fb_size.x-300
    height = fb_size.y - margin * 2
    
    cell_width = char.advance.x
    cell_height = ascender - descender
    
    cell_count_x = int(math.round_f32(width / f32(cell_width)))
    cell_count_y = int(math.round_f32(height / f32(cell_height)))
    
    width = f32(cell_width) * f32(cell_count_x)
    height = f32(cell_height) * f32(cell_count_y)
    
    terminal := terminals[index]
    if terminal == nil do return
    
    resize(&terminal^.scrollback_buffer, cell_count_y)
    
    for &row in terminal^.scrollback_buffer {
        resize(&row, cell_count_x)
    }
    
    terminal^.scroll_bottom = cell_count_y - 1
    
    when ODIN_OS == .Linux {
        TIOCSWINSZ :: 0x5414
        
        winsize :: struct {
            ws_row: u16,
            ws_col: u16,
            ws_xpixel: u16,
            ws_ypixel: u16,
        }
        
        size := winsize{
            ws_col=u16(cell_count_x),
            ws_row=u16(cell_count_y),
        }
        
        linux.ioctl(linux.Fd(terminal.master_fd), TIOCSWINSZ, uintptr(&size))
    }
}

@(private="package")
toggle_terminal_emulator :: proc() {
    context = runtime.default_context()
    
    if is_terminal_open == false {
        suppress = false
        is_terminal_open = true
        
        input_mode = .TERMINAL
        
        terminal := terminals[current_terminal_idx]
        if terminal == nil {
            new_shell := new(TtyHandle, context.allocator)
            
            new_shell ^= spawn_shell()
            
            terminals[current_terminal_idx] = new_shell
            resize_terminal(current_terminal_idx)
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
    
    terminal := terminals[current_terminal_idx]
    if terminal == nil do return
    
    sync.lock(&terminal_mutex)
    
    pen := vec2{x_pos, margin}
    
    // Draw Terminal Title
    {
        padding_sm := math.round_f32(padding * .5)
        
        title_pos := vec2{
            x_pos,
            font_base_px * 5 - (padding_sm * 2),
        }
        
        text := math.round_f32(font_base_px * normal_text_scale)
        error := ft.set_pixel_sizes(primary_font, 0, u32(text))
        assert(error == .Ok)
        ascender := f32(primary_font.size.metrics.ascender >> 6)
        descender := f32(primary_font.size.metrics.descender >> 6)
        
        bg_rect := rect{
            title_pos.x - padding - line_thickness,
            title_pos.y - padding_sm - line_thickness,
            width + padding * 2 + (line_thickness * 2),
            ascender - descender + padding_sm*2 + (line_thickness * 2),
        }
        
        sb := strings.builder_make()
        
        strings.write_string(&sb, "Term:")
        strings.write_int(&sb, current_terminal_idx)
        strings.write_string(&sb, " - ")
        strings.write_string(&sb, terminal.title)
        
        defer strings.builder_destroy(&sb)
        
        add_text(
            &text_rect_cache,
            title_pos,
            TEXT_MAIN,
            small_text,
            strings.to_string(sb),
            z_index + 1,
            true,
            -1
        )
        
        add_rect(&rect_cache, bg_rect, no_texture, border_color, vec2{}, z_index)
    }
    
    // Draw Terminal Content
    {
        bg_rect := rect{
            x_pos - padding,
            margin - padding, 
            width + padding * 2, 
            height + padding * 2,
        }
        
        add_rect(&rect_cache, bg_rect, no_texture, BG_MAIN_10, vec2{}, z_index-2)

        border_rect := rect{
            bg_rect.x - line_thickness,
            bg_rect.y - line_thickness,
            bg_rect.width + line_thickness * 2,
            bg_rect.height + line_thickness * 2,
        }
        
        add_rect(&rect_cache, border_rect, no_texture, border_color, vec2{}, z_index - 3)
    }
    
    start_row := max(0, len(terminal^.scrollback_buffer) - cell_count_y)
    end_row := min(len(terminal^.scrollback_buffer), start_row + cell_count_y)

    
    for i in start_row..<end_row {
        row := terminal^.scrollback_buffer[i]
        
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
    
    sync.unlock(&terminal_mutex)
    
    if (input_mode == .TERMINAL_TEXT_INPUT) && cursor_visible {
        cursor_rect := rect{
            x=x_pos + (f32(terminal^.cursor_col) * cell_width),
            y=margin + (f32(terminal^.cursor_row - start_row) * cell_height),
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
    
    if key == glfw.KEY_ESCAPE {
        input_mode = .TERMINAL
        
        return false
    }
        
    seq, did_allocate := map_glfw_key_to_escape_sequence(key, mods)
    
    
    if seq != "" {
        terminal := terminals[current_terminal_idx]
        if terminal == nil do return true
        
        write_to_shell(terminal^, seq)
    }
    
    if did_allocate {
        delete(seq)
    }
    
    return true
}

@(private="package")
handle_terminal_control_input :: proc() -> bool {
    /*
    if is_key_pressed(glfw.KEY_D) {
        key := key_store[glfw.KEY_D]
        
        if key.modifiers == CTRL {
            input_mode = .COMMAND
            
            return false
        }
    }*/
    
    if is_key_pressed(glfw.KEY_T) {
        key := key_store[glfw.KEY_T]
        
        if key.modifiers == CTRL {
            toggle_terminal_emulator()
            
            return false
        }
    }
    
    if is_key_pressed(glfw.KEY_I) {
        set_mode(.TERMINAL_TEXT_INPUT, glfw.KEY_I, 'i')
        
        return false
    }

    if is_key_pressed(glfw.KEY_1) {
        swap_terminal(0)
        
        return false
    }
    if is_key_pressed(glfw.KEY_2) {
        swap_terminal(1)
        
        return false
    }
    if is_key_pressed(glfw.KEY_3) {
        swap_terminal(2)
        
        return false
    }
    if is_key_pressed(glfw.KEY_4) {
        swap_terminal(3)
        
        return false
    }
    if is_key_pressed(glfw.KEY_5) {
        swap_terminal(4)
        
        return false
    }
    if is_key_pressed(glfw.KEY_6) {
        swap_terminal(5)
        
        return false
    }
    if is_key_pressed(glfw.KEY_7) {
        swap_terminal(6)
        
        return false
    }
    if is_key_pressed(glfw.KEY_8) {
        swap_terminal(7)
        
        return false
    }
    if is_key_pressed(glfw.KEY_9) {
        swap_terminal(8)
        
        return false
    }
        
    if is_key_pressed(glfw.KEY_0) {
        swap_terminal(9)
        
        return false
    }
    
    return true
}

@(private="package")
swap_terminal :: proc(index: int) {
    context = runtime.default_context()
    
    index := clamp(index, 0, 9)
    
    terminal := terminals[index]
        
    if terminal == nil {
        new_term := new(TtyHandle, context.allocator)
        new_term ^= spawn_shell()
        
        terminals[index] = new_term
        
        resize_terminal(index)
    }
    
    current_terminal_idx = index
}

@(private="package")
handle_terminal_input :: proc(key: rune) {
    terminal := terminals[current_terminal_idx]
    if terminal == nil do return
    
    bytes, n := utf8.encode_rune(key)
    
    append(&input_accumulator, ..bytes[:n])
    
    string_val := string(input_accumulator[:])
    
    write_to_shell(terminal^, string_val)
    
    clear(&input_accumulator)
}

@(private="package")
tick_terminal_emulator :: proc() {
    if suppress {
        return
    }
    
    small_text := math.round_f32(font_base_px * small_text_scale)

    if input_mode == .TERMINAL || input_mode == .TERMINAL_TEXT_INPUT {
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
ensure_scrollback_row :: proc(index: int) {
    terminal := terminals[index]
    
    if terminal == nil do return

    if terminal^.cursor_row >= len(terminal.scrollback_buffer) {
        row := make([dynamic]rune, cell_count_x)
        
        append(&terminal.scrollback_buffer, row)

        if len(terminal.scrollback_buffer) > scrollback_limit {
            ordered_remove(&terminal.scrollback_buffer, 0)
            terminal^.cursor_row -= 1
        }
        
        scroll_terminal_down(2, index)
    }
}

when ODIN_OS == .Windows {
    @(private="package")
    terminal_loop :: proc(thread: ^thread.Thread) {
    }
} else {
    @(private="package")
    terminal_loop :: proc(self: ^thread.Thread) {    
        defer fmt.println("Terminal loop exited.")
        
        last_time := glfw.GetTime()

        for !glfw.WindowShouldClose(window) {
            current_time := glfw.GetTime()
            local_frame_time := current_time - last_time
    
            if local_frame_time < target_frame_time {
                sleep_duration := (target_frame_time - local_frame_time) * f64(second)
                
                time.sleep(time.Duration(sleep_duration))                
                
                continue
            }
            
            last_time = current_time

            for &terminal, index in terminals {
                if terminal == nil do continue
                if terminal.pid == 0 do continue
            
                read_buf := make([dynamic]u8, 1024)
                defer delete(read_buf)
            
                n := posix.read(terminal.master_fd, raw_data(read_buf), len(read_buf))
                
                if n == -1 {
                    status : i32
                    
                    result := posix.waitpid(
                        posix.pid_t(terminal.pid), 
                        &status, 
                        {.NOHANG}
                    )
                    
                    if result > 0 {
                        respawn :: proc(terminal_rawptr: rawptr) {
                            terminal := cast(^TtyHandle)terminal_rawptr
                            
                            sync.lock(&terminal_mutex)
                            cleanup_tty(terminal^)
                            
                            free(terminal, context.allocator)
                            
                            terminal = nil
                            terminal = new(TtyHandle, context.allocator)                        
                            
                            sync.unlock(&terminal_mutex)
                            
                            terminal^ = spawn_shell()
                            
                            terminals[current_terminal_idx] = terminal
                            
                            resize_terminal()
                        }
                        
                        thread.run_with_data(rawptr(terminal), respawn)
                    }
                    
                    continue
                }
                
                process_ansi_chunk(string(read_buf[:n]), index)
            }
        }
    }
}

erase_line :: proc(params: [dynamic]int, index: int) {
    terminal := terminals[index]
    
    if terminal == nil do return
    
    mode := len(params) > 0 ? params[0] : 0
    switch mode {
    case 0:
        for c in terminal^.cursor_col..<cell_count_x {
            terminal^.scrollback_buffer[terminal^.cursor_row][c] = 0
        }
    case 1:
        for c in 0..=terminal^.cursor_col {
            terminal^.scrollback_buffer[terminal^.cursor_row][c] = 0
        }
    case 2:
        for c in 0..<cell_count_x {
            terminal^.scrollback_buffer[terminal^.cursor_row][c] = 0
        }
    }
}

erase_screen :: proc(params: [dynamic]int, index: int) {
    terminal := terminals[index]
    
    if terminal == nil do return
    
    mode := len(params) > 0 ? params[0] : 0

    switch mode {
    case 0:
        for r in terminal^.cursor_row..<cell_count_y {
            start_col := r == terminal^.cursor_row ? terminal^.cursor_col : 0
            for c in start_col..<cell_count_x {
                terminal^.scrollback_buffer[r][c] = 0
            }
        }
    case 1:
        for r in 0..=terminal^.cursor_row {
            end_col := r == terminal^.cursor_row ? terminal^.cursor_col : cell_count_x - 1
            for c in 0..=end_col {
                terminal^.scrollback_buffer[r][c] = 0
            }
        }
    case 2:
        for &row in terminal.scrollback_buffer {
            for &char in row {
                (&char)^ = 0
            }
        }
    }
}

parse_csi_params :: proc(s: string, index: int) -> [dynamic]int {
    params := make([dynamic]int)
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
process_ansi_chunk :: proc(input: string, index: int) {
    terminal := terminals[index]
    
    if terminal == nil do return
    
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
                if terminal^.cursor_col > 0 {
                    terminal^.cursor_col -= 1
                    terminal^.scrollback_buffer[terminal^.cursor_row][terminal^.cursor_col] = 0
                } else if terminal^.cursor_row > 0 {
                    terminal^.cursor_row -= 1
                    terminal^.cursor_col = cell_count_x - 1
                    terminal^.scrollback_buffer[terminal^.cursor_row][terminal^.cursor_col] = 0
                }
                
                continue
            }

            if b == 0x07 { // bell
                continue
            }

            if b == 0x0A {
                newline(index)
                continue
            }

            if b == 0x0D {
                terminal^.cursor_col = 0
                continue
            }
            
            if b == 0x09 {
                for i := terminal.cursor_col; i % 8 != 0; i += 1 {
                    if terminal^.cursor_row >= len(terminal^.scrollback_buffer) {
                        ensure_scrollback_row(index)
                        terminal^.cursor_row = len(terminal^.scrollback_buffer) - 1
                    }
                
                    if terminal^.cursor_col >= cell_count_x {
                        terminal^.cursor_col = 0
                        newline(index)
                    }
                    
                    terminal^.cursor_col += 1
                }
                
                continue
            }
            
            if b < 0x20 {
                continue
            }

            r := utf8.rune_at(input, i)
            size := utf8.rune_size(r)
            handle_normal_char(r, index)
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
                handle_simple_escape(ansi_buf[:], index)
                ansi_state = .Normal
                
                clear(&ansi_buf)
            }

        case .Csi:
            append(&ansi_buf, b)
            if b >= 0x40 && b <= 0x7E {
                handled := handle_csi_seq(string(ansi_buf[:]), index)
                
                if !handled {
                    fmt.println("csi was not handled!!")
                }
                
                ansi_state = .Normal
                
                clear(&ansi_buf)
            }
            

        case .Osc:
            append(&ansi_buf, b)
            if b == 0x07 { // BEL terminator
                handle_osc_seq(string(ansi_buf[:]), index)
                ansi_state = .Normal
                
                clear(&ansi_buf)
            } else if b == 0x1B && i + 1 < len(input) && input[i+1] == '\\' {
                append(&ansi_buf, input[i+1])
                i += 1
                handle_osc_seq(string(ansi_buf[:]), index)
                ansi_state = .Normal
                
                clear(&ansi_buf)
            }
        }
    }
}

newline :: proc(index: int) {
    terminal := terminals[index]
    
    if terminal == nil do return
    
    row := &terminal.cursor_row
    row^ += 1
    
    if terminal^.cursor_row > terminal^.scroll_bottom {
        scroll_region_up(index)
        row^ = terminal^.scroll_bottom
    }
}

scroll_region_up :: proc(index: int) {
    terminal := terminals[index]
    
    if terminal == nil do return
    
    for r in terminal^.scroll_top..<terminal^.scroll_bottom {
        clear(&terminal.scrollback_buffer[r])
        append(&terminal.scrollback_buffer[r], ..terminal.scrollback_buffer[r+1][:])
    }

    last_row := terminal^.scroll_bottom
    for c in 0..<cell_count_x {
        terminal^.scrollback_buffer[last_row][c] = 0
    }
}

handle_simple_escape :: proc(seq: []u8, index: int) {
    terminal := terminals[index]
    
    if terminal == nil do return
    
    if len(seq) < 2 { return }
    switch seq[1] {
    case '7':
        terminal^.stored_cursor_row = terminal^.cursor_row
        terminal^.stored_cursor_col = terminal^.cursor_col
    case '8':
        terminal^.cursor_row = terminal^.stored_cursor_row
        terminal^.cursor_col = terminal^.stored_cursor_col
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

handle_osc_seq :: proc(seq: string, index: int) {
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
        
        terminals[index].title = utf8.runes_to_string(sanitized[:])
        
        delete(sanitized)
    }
}

handle_normal_char :: proc(r: rune, index: int) {
    terminal := terminals[index]
    
    if terminal == nil do return
    
    if terminal^.cursor_col >= len(terminal.scrollback_buffer[terminal.cursor_row]) {
        terminal^.cursor_col = 0
        newline(index)
    }
    
    if terminal^.cursor_row >= len(terminal.scrollback_buffer) {
        ensure_scrollback_row(index)
        terminal^.cursor_row = len(terminal.scrollback_buffer) - 1
    }


    terminal^.scrollback_buffer[terminal^.cursor_row][terminal^.cursor_col] = r
    terminal^.cursor_col += 1
}

handle_csi_seq :: proc(seq: string, index: int) -> (handled: bool) {
    if len(seq) < 2 { return false }
    
    terminal := terminals[index]
    
    if terminal == nil do return false

    final := seq[len(seq)-1]
    params_str := len(seq) > 2 ? seq[2:len(seq)-1] : ""
    params := parse_csi_params(params_str, index)

    switch final {
    case 'H', 'f':
        row := len(params) >= 1 && params[0] > 0 ? params[0] - 1 : 0
        col := len(params) >= 2 && params[1] > 0 ? params[1] - 1 : 0
        terminal^.cursor_row = clamp(row, 0, cell_count_y - 1)
        
        terminal^.cursor_col = clamp(col, 0, cell_count_x - 1)
        
        return true
    case 'A':
        delta := len(params) > 0 ? params[0] : 1
        terminal^.cursor_row = clamp(terminal^.cursor_row - delta, 0, cell_count_y - 1)
        
        return true

    case 'B':
        delta := len(params) > 0 ? params[0] : 1
        terminal^.cursor_row = clamp(terminal^.cursor_row + delta, 0, cell_count_y - 1)

        return true
    case 'C':
        delta := len(params) > 0 ? params[0] : 1
        terminal^.cursor_col = clamp(terminal^.cursor_col + delta, 0, cell_count_x - 1)

        return true
    case 'D':
        delta := len(params) > 0 ? params[0] : 1
        terminal^.cursor_col = clamp(terminal^.cursor_col - delta, 0, cell_count_x - 1)

        return true
    case 'E':
        delta := len(params) > 0 ? params[0] : 1
        terminal^.cursor_row = clamp(terminal^.cursor_row + delta, 0, cell_count_y - 1)
        
        terminal^.cursor_col = 0

        return true
    case 'F':
        delta := len(params) > 0 ? params[0] : 1
        terminal^.cursor_row = clamp(terminal^.cursor_row - delta, 0, cell_count_y - 1)
        
        terminal^.cursor_col = 0

        return true
    case 'G':
        col := len(params) > 0 ? params[0] - 1 : 0
        terminal^.cursor_col = clamp(col, 0, cell_count_x - 1)

        return true
    case 'J':
        erase_screen(params, index)

        return true
    case 'K':
        erase_line(params, index)

        return true
    case 'L':
        insert_lines(len(params) > 0 ? params[0] : 1, index)

        return true
    case 'M':
        delete_lines(len(params) > 0 ? params[0] : 1, index)

        return true
    case 'P':
        delete_chars(len(params) > 0 ? params[0] : 1, index)

        return true
    case '@':
        insert_chars(len(params) > 0 ? params[0] : 1, index)

        return true
    case 'm':
        set_graphics_rendition(params, index)

        return true
    case 'r':
        set_scroll_region(params, index)

        return true
    case 's':
        terminal^.stored_cursor_row = terminal^.cursor_row
        terminal^.stored_cursor_col = terminal^.cursor_col

        return true
    case 'u':
        terminal^.cursor_row = terminal^.stored_cursor_row
        terminal^.cursor_col = terminal^.stored_cursor_col

        return true
    case 'c':
        // respond("\x1b[?1;0c") // "VT100"

        return true
    case '?':
        handle_private_mode(seq, index)
        
        return true
    case:
        fmt.println("CSI, unhandled final rune.", final)
        
        return false
    }
    
    
    return false
}

handle_private_mode :: proc(seq: string, index: int) {
    if strings.contains(seq, "?1049h") {
        enable_alt_buffer(index)
    } else if strings.contains(seq, "?1049l") {
        disable_alt_buffer(index)
    } else if strings.contains(seq, "?25l") {
        cursor_visible = false
    } else if strings.contains(seq, "?25h") {
        cursor_visible = true
    }
}

set_scroll_region :: proc(params: [dynamic]int, index: int) {
    terminal := terminals[index]
    
    if terminal == nil do return

    t := len(params) > 0 ? params[0] - 1 : 0
    b := len(params) > 1 ? params[1] - 1 : cell_count_y - 1
    terminal^.scroll_top = clamp(t, 0, cell_count_y - 1)
    terminal^.scroll_bottom = clamp(b, terminal^.scroll_top, cell_count_y - 1)
    terminal^.cursor_row = terminal^.scroll_top
}

insert_lines :: proc(n: int, index: int) { }
delete_lines :: proc(n: int, index: int) { }
insert_chars :: proc(n: int, index: int) { }
delete_chars :: proc(n: int, index: int) { }

enable_alt_buffer :: proc(index: int) {
    terminal := terminals[index]
    
    if terminal == nil do return

    resize(&terminal.alt_buffer, len(terminal.scrollback_buffer))
    
    for i in 0..<len(terminal.scrollback_buffer) {
        terminal^.alt_buffer[i] = make([dynamic]rune, cell_count_x)
        
        for j in 0..<cell_count_x {
            terminal^.alt_buffer[i][j] = terminal.scrollback_buffer[i][j]
        }
    }
    
    clear(&terminal.scrollback_buffer)
    
    terminal^.using_alt_buffer = true
}

disable_alt_buffer :: proc(index: int) {
    terminal := terminals[index]
    
    if terminal == nil do return

    clear(&terminal.scrollback_buffer)
    resize(&terminal.scrollback_buffer, len(terminal.alt_buffer))
    
    for i in 0..<len(terminal.alt_buffer) {
        terminal^.scrollback_buffer[i] = make([dynamic]rune, cell_count_x)
        
        for j in 0..<cell_count_x {
            terminal^.scrollback_buffer[i][j] = terminal^.alt_buffer[i][j]
        }
    }
    
    terminal^.using_alt_buffer = false
}

set_graphics_rendition :: proc(params: [dynamic]int, index: int) {
    fmt.println("GRAPHICS RENDITION PARAMS: ", params)
}
