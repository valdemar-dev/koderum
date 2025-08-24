#+private file
package main

/*
    TERMINAL EMULATOR REIVIONS TWO!
    This version is about 5% less jank.
    It can run things like VIM and BTOP, and FASFETCH without issue.. for the most part.
    
    Please contribute to this! I hate EVERYTHING to do with terminals!
*/

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

@(private="package")
terminal_debug_mode : bool = false

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

    rw_mutex: sync.RW_Mutex,
    ansi_state: Ansi_State,
    ansi_buf: [dynamic]u8,
    cursor_visible: bool,
}

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

@(private="package")
scroll_terminal_up :: proc(lines: int = 1, index: int = current_terminal_idx) {
    terminal := terminals[index]
    if terminal == nil { return }

    buf := &terminal.scrollback_buffer if !terminal.using_alt_buffer else &terminal.alt_buffer

    sync.lock(&terminal.rw_mutex)
    defer sync.unlock(&terminal.rw_mutex)

    for _ in 0..<lines {
        start_row_in_buf := max(0, len(buf) - cell_count_y)
        region_top := start_row_in_buf + terminal.scroll_top
        region_bottom := start_row_in_buf + terminal.scroll_bottom

        if terminal.scroll_top == 0 && !terminal.using_alt_buffer {
            blank := make([dynamic]rune, cell_count_x)
            
            for &c in blank { c = ' ' }
            
            append(buf, blank)
            
            if len(buf) > scrollback_limit {
                delete(buf[0])
                ordered_remove(buf, 0)
            }
        } else {
            discarded := buf[region_top]
            for r := region_top; r < region_bottom; r += 1 {
                buf[r] = buf[r + 1]
            }
            
            buf[region_bottom] = make([dynamic]rune, cell_count_x)
            
            for &c in buf[region_bottom] { c = ' ' }
            
            delete(discarded)
        }
    }
}

@(private="package")
scroll_terminal_down :: proc(lines: int = 1, index: int = current_terminal_idx) {
    terminal := terminals[index]
    if terminal == nil { return }

    buf := &terminal.scrollback_buffer if !terminal.using_alt_buffer else &terminal.alt_buffer

    sync.lock(&terminal.rw_mutex)
    defer sync.unlock(&terminal.rw_mutex)

    for _ in 0..<lines {
        start_row_in_buf := max(0, len(buf) - cell_count_y)
        region_top := start_row_in_buf + terminal.scroll_top
        region_bottom := start_row_in_buf + terminal.scroll_bottom

        if terminal.scroll_top == 0 && !terminal.using_alt_buffer {
            discarded := buf[len(buf) - 1]
            ordered_remove(buf, len(buf) - 1)
            blank := make([dynamic]rune, cell_count_x)
            
            for &c in blank { c = ' ' }
            
            inject_at(buf, 0, blank)
            delete(discarded)
        } else {
            discarded := buf[region_bottom]
            for r := region_bottom; r > region_top; r -= 1 {
                buf[r] = buf[r - 1]
            }
            buf[region_top] = make([dynamic]rune, cell_count_x)
            for &c in buf[region_top] { c = ' ' }
            delete(discarded)
        }
    }
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
        
        return termios
    }
    
    restore_parent_termios :: proc(termios: ^posix.termios) {
        err := posix.tcsetattr(0, posix.TC_Optional_Action.TCSANOW, termios)
        if err != posix.result.OK {
            fmt.println("Failed to restore parent termios")
        }
    }
    
    cleanup_tty :: proc(tty: TtyHandle) {
        posix.close(tty.master_fd)
        posix.waitpid(posix.pid_t(tty.pid), nil, {})
        
        delete(tty.scrollback_buffer)
        delete(tty.alt_buffer)
        delete(tty.title)
        delete(tty.ansi_buf)
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
            termios.c_iflag = {.BRKINT, .ICRNL, .IXON, .IXANY}
            termios.c_oflag = {.OPOST, .ONLCR}
            termios.c_cflag = {.CREAD, .CS8, .HUPCL}
            termios.c_lflag = {.ICANON, .ISIG, .IEXTEN, .ECHO, .ECHOE, .ECHOK, .ECHONL}
            termios.c_cc[posix.Control_Char.VEOF] = 4
            termios.c_cc[posix.Control_Char.VEOL] = 0
            termios.c_cc[posix.Control_Char.VERASE] = 0x7f
            termios.c_cc[posix.Control_Char.VINTR] = 3
            termios.c_cc[posix.Control_Char.VKILL] = 21
            termios.c_cc[posix.Control_Char.VMIN] = 1
            termios.c_cc[posix.Control_Char.VQUIT] = 28
            termios.c_cc[posix.Control_Char.VSTART] = 17
            termios.c_cc[posix.Control_Char.VSTOP] = 19
            termios.c_cc[posix.Control_Char.VSUSP] = 26
            termios.c_cc[posix.Control_Char.VTIME] = 0
    
            err := posix.tcsetattr(slave_fd, posix.TC_Optional_Action.TCSANOW, &termios)
            assert(err == posix.result.OK)
    
            posix.close(master_fd)
            posix.close(slave_fd)
            posix.setenv("TERM", "xterm", true)
    
            posix.execl("/bin/bash", "bash", nil)
            posix._exit(1)
        }
    
        posix.dup2(0, 0)
        posix.dup2(1, 1)
        posix.dup2(2, 2)
    
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
            {},
            .Normal,
            make([dynamic]u8),
            true,
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

@(private="package")
resize_terminal :: proc (index: int = current_terminal_idx) {
    if terminal_debug_mode {
        fmt.println("Terminal Debugger: Resizing Terminal")
    }
    
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

    
    terminal^.scroll_bottom = cell_count_y - 1
    terminal^.scroll_top = 0
    
    for &row in terminal^.scrollback_buffer {
        resize(&row, cell_count_x)
        
        for c := len(row); c < cell_count_x; c += 1 {
            row[c] = ' '
        }
    }
    
    for len(terminal^.scrollback_buffer) < cell_count_y {
        blank := make([dynamic]rune, cell_count_x)
        for &c in blank { c = ' ' }
        append(&terminal^.scrollback_buffer, blank)
    }
    
    delete(terminal^.alt_buffer)
    terminal^.alt_buffer = make([dynamic][dynamic]rune, cell_count_y)
    for i in 0..<cell_count_y {
        terminal^.alt_buffer[i] = make([dynamic]rune, cell_count_x)
        for &c in terminal^.alt_buffer[i] { c = ' ' }
    }
    
    terminal^.cursor_row = clamp(terminal^.cursor_row, 0, cell_count_y - 1)
    terminal^.cursor_col = clamp(terminal^.cursor_col, 0, cell_count_x - 1)
    
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
    if terminal_debug_mode {
        fmt.println("Terminal Debugger: Toggling Terminal Emulator")
    }

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
    
    buf := terminal.using_alt_buffer ? terminal.alt_buffer : terminal.scrollback_buffer
    start_row := max(0, len(buf) - cell_count_y)
    num_displayed := min(len(buf) - start_row, cell_count_y)
    
    for local_i in 0..<num_displayed {
        i := start_row + local_i
        row := buf[i]
        
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
    
    if (input_mode == .TERMINAL_TEXT_INPUT) && terminal.cursor_visible {
        cursor_rect := rect{
            x=x_pos + (f32(terminal^.cursor_col) * cell_width),
            y=margin + (f32(terminal^.cursor_row) * cell_height),
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
    
    draw_rects(&rect_cache)
    draw_rects(&text_rect_cache)
}


@(private="package")
handle_terminal_emulator_input :: proc(key, scancode, action, mods: i32) -> (do_continue: bool) {
    if action == glfw.RELEASE do return true
    
    if key == glfw.KEY_ESCAPE && is_key_down(glfw.KEY_LEFT_CONTROL) {
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
    if terminal_debug_mode {
        fmt.println("Terminal Debugger: Swapping Terminal")
    }

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
                sleep_duration := (target_frame_time - local_frame_time) * f64(time.Second)
                
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
                            terminal_ptr := cast(^TtyHandle)terminal_rawptr
                            
                            sync.lock(&terminal_ptr^.rw_mutex)
                            cleanup_tty(terminal_ptr^)
                            sync.unlock(&terminal_ptr^.rw_mutex)
                            
                            free(terminal_ptr, context.allocator)
                            
                            terminal_ptr = nil
                            terminal_ptr = new(TtyHandle, context.allocator)                        
                            
                            terminal_ptr^ = spawn_shell()
                            
                            terminals[current_terminal_idx] = terminal_ptr
                            
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
    if terminal == nil { return }

    buf := terminal.using_alt_buffer ? terminal.alt_buffer : terminal.scrollback_buffer
    start_row_in_buf := max(0, len(buf) - cell_count_y)
    row_idx := start_row_in_buf + terminal.cursor_row

    mode := len(params) > 0 ? params[0] : 0
    switch mode {
    case 0:
        for c in terminal.cursor_col..<cell_count_x {
            buf[row_idx][c] = ' '
        }
    case 1:
        for c in 0..=terminal.cursor_col {
            buf[row_idx][c] = ' '
        }
    case 2:
        for c in 0..<cell_count_x {
            buf[row_idx][c] = ' '
        }
    }
}

erase_screen :: proc(params: [dynamic]int, index: int) {
    terminal := terminals[index]
    if terminal == nil { return }

    buf := terminal.using_alt_buffer ? terminal.alt_buffer : terminal.scrollback_buffer
    start_row_in_buf := max(0, len(buf) - cell_count_y)

    mode := len(params) > 0 ? params[0] : 0

    switch mode {
    case 0:
        for r in terminal.cursor_row..<cell_count_y {
            row_idx := start_row_in_buf + r
            start_col := r == terminal.cursor_row ? terminal.cursor_col : 0
            for c in start_col..<cell_count_x {
                buf[row_idx][c] = ' '
            }
        }
    case 1:
        for r in 0..=terminal.cursor_row {
            row_idx := start_row_in_buf + r
            end_col := r == terminal.cursor_row ? terminal.cursor_col : cell_count_x - 1
            for c in 0..=end_col {
                buf[row_idx][c] = ' '
            }
        }
    case 2:
        for r in 0..<cell_count_y {
            row_idx := start_row_in_buf + r
            for c in 0..<cell_count_x {
                buf[row_idx][c] = ' '
            }
        }
    }
}

parse_csi :: proc(s: string) -> (private: rune, params: [dynamic]int) {
    params = make([dynamic]int)
    if len(s) == 0 {
        return
    }

    params_str := s
    if s[0] < '0' || s[0] > '9' {
        private = rune(s[0])
        params_str = s[1:]
    }

    parts := strings.split(params_str, ";")
    defer delete(parts)

    for p in parts {
        if len(p) == 0 {
            append(&params, 0)
        } else {
            val, ok := strconv.parse_int(p, 10)
            append(&params, ok ? int(val) : 0)
        }
    }
    return
}

process_ansi_chunk :: proc(input: string, index: int) {
    if terminal_debug_mode {
        fmt.println("Terminal Debugger: Processing ANSI Chunk.", transmute([]u8)input)
    }

    terminal := terminals[index]
    if terminal == nil { return }

    for i := 0; i < len(input); i += 1 {
        b := input[i]

        switch terminal.ansi_state {
        case .Normal:
            if b == 0x1B { // esc key
                terminal.ansi_state = .Esc
                clear(&terminal.ansi_buf)
                append(&terminal.ansi_buf, b)
                continue
            }

            if b == 0x08 { // backspace
                if terminal.cursor_col > 0 {
                    terminal.cursor_col -= 1
                } else if terminal.cursor_row > 0 {
                    terminal.cursor_row -= 1
                    terminal.cursor_col = cell_count_x - 1
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
                terminal.cursor_col = 0
                continue
            }
            
            if b == 0x09 { // tab
                tab_stop := ((terminal.cursor_col / 8) + 1) * 8
                terminal.cursor_col = min(tab_stop, cell_count_x - 1)
                continue
            }
            
            if b < 0x20 {
                continue
            }

            r, size := utf8.decode_rune(input[i:])
            handle_normal_char(r, index)
            i += size - 1
            
            continue

        case .Esc:
            append(&terminal.ansi_buf, b)
            if b == '[' {
                terminal.ansi_state = .Csi
                continue
            } else if b == ']' {
                terminal.ansi_state = .Osc
                continue
            } else {
                handle_simple_escape(terminal.ansi_buf[:], index)
                terminal.ansi_state = .Normal
                
                clear(&terminal.ansi_buf)
                
                continue
            }

        case .Csi:
            append(&terminal.ansi_buf, b)
            if b >= 0x40 && b <= 0x7E {
                handled := handle_csi_seq(string(terminal.ansi_buf[:]), index)
                
                if !handled {
                    fmt.println("Unhandled CSI Sequence! Contained Bytes:", "(", terminal.ansi_buf[:], ")")
                }
                
                clear(&terminal.ansi_buf)
                
                terminal.ansi_state = .Normal
            }
            
            continue
        case .Osc:
            append(&terminal.ansi_buf, b)
            if b == 0x07 {
                handle_osc_seq(string(terminal.ansi_buf[:]), index)
                terminal.ansi_state = .Normal
                
                clear(&terminal.ansi_buf)
            } else if b == 0x1B && i + 1 < len(input) && input[i+1] == '\\' {
                append(&terminal.ansi_buf, input[i+1])
                i += 1
                handle_osc_seq(string(terminal.ansi_buf[:]), index)
                terminal.ansi_state = .Normal
                
                clear(&terminal.ansi_buf)
            }
            continue
        }
    }
}

newline :: proc(index: int) {
    terminal := terminals[index]
    if terminal == nil { return }

    terminal.cursor_row += 1
    if terminal.cursor_row > terminal.scroll_bottom {
        scroll_terminal_up(1, index)
        terminal.cursor_row = terminal.scroll_bottom
    }
}

handle_simple_escape :: proc(seq: []u8, index: int) {
    if terminal_debug_mode {
        fmt.println("Terminal Debugger: Handling Simple Escape", seq)
    }

    terminal := terminals[index]
    
    if terminal == nil do return
    
    if len(seq) < 2 { return }
    switch seq[1] {
    case '7':
        terminal^.stored_cursor_row = terminal^.cursor_row
        terminal^.stored_cursor_col = terminal^.cursor_col
    case '8':
        terminal^.cursor_row = clamp(terminal^.stored_cursor_row, 0, cell_count_y - 1)
        terminal^.cursor_col = clamp(terminal^.stored_cursor_col, 0, cell_count_x - 1)
    case '=': // application Keypad Mode Enable
    case '>': // normal Keypad Mode Enable
    case 'c': // full reset (RIS)
        reset_terminal(index)
    }
}

reset_terminal :: proc(index: int) {
    terminal := terminals[index]
    if terminal == nil { return }

    erase_screen(make([dynamic]int), index)
    terminal.cursor_row = 0
    terminal.cursor_col = 0
    terminal.scroll_top = 0
    terminal.scroll_bottom = cell_count_y - 1
}

sanitize_title :: proc(s: string) -> [dynamic]rune {
    result := make([dynamic]rune)
    
    for r in s {
        if r >= 0x20 || r == '\t' {
            append(&result, r)
        }
    }
    return result
}

handle_osc_seq :: proc(seq: string, index: int) {
    if terminal_debug_mode {
        fmt.println("Terminal Debugger: Handling OSC Seq, ", transmute([]u8)seq)
    }

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
    if terminal == nil { return }

    buf := terminal.using_alt_buffer ? terminal.alt_buffer : terminal.scrollback_buffer
    start_row_in_buf := max(0, len(buf) - cell_count_y)

    if terminal.cursor_col >= cell_count_x {
        terminal.cursor_col = 0
        newline(index)
    }

    if terminal.cursor_row >= cell_count_y {
        scroll_terminal_up(1, index)
        terminal.cursor_row = cell_count_y - 1
    }

    row_idx := start_row_in_buf + terminal.cursor_row
    buf[row_idx][terminal.cursor_col] = r
    terminal.cursor_col += 1
}

handle_csi_seq :: proc(seq: string, index: int) -> (handled: bool) {
    if terminal_debug_mode {
        fmt.println("Terminal Debugger: Handling CSI Seq,", transmute([]u8)seq)
    }

    if len(seq) < 2 { return false }
    
    terminal := terminals[index]
    
    if terminal == nil do return false

    final := rune(seq[len(seq)-1])
    params_str := len(seq) > 2 ? seq[2:len(seq)-1] : ""
    private, raw_params := parse_csi(params_str)
    params := raw_params
    defer delete(raw_params)

    if private != 0 {
        switch private {
        case '?':
            switch final {
            case 'h', 'l':
                set_reset_private_mode(final == 'h', params, index)
                return true
            case 'J':
                erase_screen(params, index)
                return true
            case 'K':
                erase_line(params, index)
                return true
            case 'u':
                write_to_shell(terminal^, "\x1b[?0u")
                return true
            }
        case '>':
            if final == 'c' {
                ps := len(params) > 0 ? params[0] : 0
                if ps == 0 || ps == 2 {
                    write_to_shell(terminal^, "\x1b[>0;10;0c")
                }
                return true
            }
        }
        return false
    }

    is_movement := final == 'A' || final == 'B' || final == 'C' || final == 'D' || final == 'E' || final == 'F'
    is_position := final == 'H' || final == 'G'
    for &p in params {
        if p == 0 {
            if is_movement || is_position {
                p = 1
            }
        }
    }

    switch final {
    case 'H', 'f':
        row := len(params) >= 1 ? params[0] - 1 : 0
        col := len(params) >= 2 ? params[1] - 1 : 0
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
    case 'd':
        row := len(params) > 0 ? params[0] - 1 : 0
        terminal^.cursor_row = clamp(row, 0, cell_count_y - 1)
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
        n := len(params) > 0 ? params[0] : 1
        insert_lines(n, index)

        return true
    case 'M':
        n := len(params) > 0 ? params[0] : 1
        delete_lines(n, index)

        return true
    case 'P':
        n := len(params) > 0 ? params[0] : 1
        delete_chars(n, index)

        return true
    case '@':
        n := len(params) > 0 ? params[0] : 1
        insert_chars(n, index)

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
        terminal^.cursor_row = clamp(terminal^.stored_cursor_row, 0, cell_count_y - 1)
        terminal^.cursor_col = clamp(terminal^.stored_cursor_col, 0, cell_count_x - 1)

        return true
    case 'c':
        ps := len(params) > 0 ? params[0] : 0
        if ps == 0 {
            write_to_shell(terminal^, "\x1b[?6c") // VT220
        }
        return true
    case:
        fmt.println("CSI, unhandled final rune.", final)
        
        return false
    }
    
    return false
}

set_reset_private_mode :: proc(set: bool, params: [dynamic]int, index: int) {
    terminal := terminals[index]
    if terminal == nil { return }

    for param in params {
        switch param {
        case 25:
            terminal.cursor_visible = set
        case 1049:
            if set {
                enable_alt_buffer(index)
            } else {
                disable_alt_buffer(index)
            }
        }
    }
}

set_scroll_region :: proc(params: [dynamic]int, index: int) {
    terminal := terminals[index]
    
    if terminal == nil do return

    t := len(params) > 0 ? params[0] - 1 : 0
    b := len(params) > 1 ? params[1] - 1 : cell_count_y - 1
    terminal^.scroll_top = clamp(t, 0, cell_count_y - 1)
    terminal^.scroll_bottom = clamp(b, terminal^.scroll_top, cell_count_y - 1)
    terminal^.cursor_row = 0
    terminal^.cursor_col = 0
}

insert_lines :: proc(n: int, index: int) {
    terminal := terminals[index]
    if terminal == nil { return }

    saved_top := terminal.scroll_top
    saved_bottom := terminal.scroll_bottom
    terminal.scroll_top = terminal.cursor_row
    terminal.scroll_bottom = cell_count_y - 1

    scroll_terminal_down(n, index)

    terminal.scroll_top = saved_top
    terminal.scroll_bottom = saved_bottom
}

delete_lines :: proc(n: int, index: int) {
    terminal := terminals[index]
    if terminal == nil { return }

    saved_top := terminal.scroll_top
    saved_bottom := terminal.scroll_bottom
    terminal.scroll_top = terminal.cursor_row
    terminal.scroll_bottom = cell_count_y - 1

    scroll_terminal_up(n, index)

    terminal.scroll_top = saved_top
    terminal.scroll_bottom = saved_bottom
}

insert_chars :: proc(n: int, index: int) {
    terminal := terminals[index]
    if terminal == nil { return }

    buf := terminal.using_alt_buffer ? terminal.alt_buffer : terminal.scrollback_buffer
    start_row_in_buf := max(0, len(buf) - cell_count_y)
    row_idx := start_row_in_buf + terminal.cursor_row
    row := buf[row_idx]

    effective_n := min(n, cell_count_x - terminal.cursor_col)

    for c := cell_count_x - 1; c >= terminal.cursor_col + effective_n; c -= 1 {
        row[c] = row[c - effective_n]
    }
    for c := terminal.cursor_col; c < terminal.cursor_col + effective_n; c += 1 {
        row[c] = ' '
    }
}

delete_chars :: proc(n: int, index: int) {
    terminal := terminals[index]
    if terminal == nil { return }

    buf := terminal.using_alt_buffer ? terminal.alt_buffer : terminal.scrollback_buffer
    start_row_in_buf := max(0, len(buf) - cell_count_y)
    row_idx := start_row_in_buf + terminal.cursor_row
    row := buf[row_idx]

    effective_n := min(n, cell_count_x - terminal.cursor_col)

    for c := terminal.cursor_col; c < cell_count_x - effective_n; c += 1 {
        row[c] = row[c + effective_n]
    }
    for c := cell_count_x - effective_n; c < cell_count_x; c += 1 {
        row[c] = ' '
    }
}

enable_alt_buffer :: proc(index: int) {
    if terminal_debug_mode {
        fmt.println("Terminal Debugger: Enabling Alt Buffer.")
    }

    terminal := terminals[index]
    if terminal == nil { return }

    terminal.stored_cursor_row = terminal.cursor_row
    terminal.stored_cursor_col = terminal.cursor_col
    terminal.using_alt_buffer = true
    terminal.cursor_row = 0
    terminal.cursor_col = 0
    terminal.scroll_top = 0
    terminal.scroll_bottom = cell_count_y - 1

    for &row in terminal.alt_buffer {
        for &c in row {
            c = ' '
        }
    }
}

disable_alt_buffer :: proc(index: int) {
    if terminal_debug_mode {
        fmt.println("Terminal Debugger: Disabling Alt Buffer.")
    }

    terminal := terminals[index]
    if terminal == nil { return }

    terminal.using_alt_buffer = false
    terminal.cursor_row = clamp(terminal.stored_cursor_row, 0, cell_count_y - 1)
    terminal.cursor_col = clamp(terminal.stored_cursor_col, 0, cell_count_x - 1)
}

set_graphics_rendition :: proc(params: [dynamic]int, index: int) {
    if terminal_debug_mode {
        fmt.println("Terminal Debugger: Setting Graphics Rendition")
    }
}