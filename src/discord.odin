#+feature dynamic-literals
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:encoding/json"
import "core:time"
import "core:thread"
import "core:mem"
import "base:runtime"
import "core:strconv"
import posix "core:sys/posix"

Opcode :: enum u32 {
    Handshake = 0,
    Frame     = 1,
    Close     = 2,
    Ping      = 3,
    Pong      = 4,
}

discord_client_id :: "1376924413219569795"

discord_socket_fd: posix.FD = -1
discord_ipc_thread: ^thread.Thread

DiscordClient :: struct {
    pid: i32,
}

discord_client: DiscordClient

write_full :: proc(fd: posix.FD, data: []u8) -> bool {
    to_write := len(data)
    written := 0
    for written < to_write {
        n := posix.write(fd, raw_data(data[written:]), uint(to_write - written))
        if n <= 0 {
            return false
        }
        written += int(n)
    }
    return true
}

read_full :: proc(fd: posix.FD, buf: []u8) -> bool {
    to_read := len(buf)
    read := 0
    for read < to_read {
        n := posix.read(fd, raw_data(buf[read:]), uint(to_read - read))
        if n <= 0 {
            return false
        }
        read += int(n)
    }
    return true
}

send_json :: proc(fd: posix.FD, op: Opcode, val: json.Value) -> bool {
    data, err := json.marshal(val, allocator = context.temp_allocator)
    if err != nil {
        fmt.eprintln("Failed to marshal JSON")
        return false
    }
    return send_data(fd, op, data)
}

send_data :: proc(fd: posix.FD, op: Opcode, data: []u8) -> bool {
    op_u32 := u32(op)
    len_u32 := u32(len(data))
    header: [8]u8
    // Opcode little-endian
    header[0] = u8(op_u32 & 0xFF)
    header[1] = u8((op_u32 >> 8) & 0xFF)
    header[2] = u8((op_u32 >> 16) & 0xFF)
    header[3] = u8((op_u32 >> 24) & 0xFF)
    // Length little-endian
    header[4] = u8(len_u32 & 0xFF)
    header[5] = u8((len_u32 >> 8) & 0xFF)
    header[6] = u8((len_u32 >> 16) & 0xFF)
    header[7] = u8((len_u32 >> 24) & 0xFF)

    if !write_full(fd, header[:]) {
        fmt.eprintln("Failed to write header to Discord IPC socket")
        return false
    }
    if !write_full(fd, data) {
        fmt.eprintln("Failed to write data to Discord IPC socket")
        return false
    }
    return true
}

discord_ipc_loop :: proc(t: ^thread.Thread) {
    context = runtime.default_context()
    
    for {
        header: [8]u8
        if !read_full(discord_socket_fd, header[:]) {
            fmt.println("Failed to read header from Discord IPC")
            break
        }

        op_u32 := u32(header[0]) | (u32(header[1]) << 8) | (u32(header[2]) << 16) | (u32(header[3]) << 24)
        len_u32 := u32(header[4]) | (u32(header[5]) << 8) | (u32(header[6]) << 16) | (u32(header[7]) << 24)

        if len_u32 > 0 {
            data_buf := make([]u8, len_u32, context.temp_allocator)
            if !read_full(discord_socket_fd, data_buf) {
                fmt.println("Failed to read data from Discord IPC")
                break
            }

            op := Opcode(op_u32)
            switch op {
            case .Ping:
                send_data(discord_socket_fd, .Pong, data_buf)
            case .Frame:
                j, err := json.parse(data_buf)
                if err == nil {
                    defer json.destroy_value(j)
                    obj, ok := j.(json.Object)
                    if ok {
                        evt_val, has_evt := obj["evt"]
                        if has_evt {
                            evt, is_str := evt_val.(string)
                            if is_str {
                                if evt == "ERROR" {
                                    fmt.println("Error from Discord:", obj)
                                } else if evt == "READY" {
                                    fmt.println("Discord READY received")
                                }
                            }
                        }
                    }
                }
            case .Close:
                fmt.println("Close received from Discord")
                break
            case .Handshake, .Pong:
            }
        }
    }
    posix.close(discord_socket_fd)
    discord_socket_fd = -1
}

connect_discord_ipc :: proc() {
    discord_client.pid = i32(posix.getpid())

    socket_path: string
    xdg_runtime_dir := os.get_env("XDG_RUNTIME_DIR")
    if xdg_runtime_dir != "" {
        socket_path = strings.join({xdg_runtime_dir, "discord-ipc-0"}, "/", context.temp_allocator)
    } else {
        tmpdir := os.get_env("TMPDIR")
        if tmpdir == "" {
            tmpdir = "/tmp"
        }
        socket_path = strings.join({tmpdir, "discord-ipc-0"}, "/", context.temp_allocator)
    }

    discord_socket_fd = posix.socket(posix.AF.UNIX, posix.Sock.STREAM, posix.Protocol(0))
    if discord_socket_fd < 0 {
        fmt.eprintln("Failed to create socket for Discord IPC")
        return
    }

    addr: posix.sockaddr_un = {}
    addr.sun_family = posix.sa_family_t(posix.AF.UNIX)
    path_bytes := transmute([]u8)socket_path
    mem.copy(&addr.sun_path[0], raw_data(path_bytes), min(len(path_bytes), size_of(addr.sun_path) - 1))

    if posix.connect(discord_socket_fd, cast(^posix.sockaddr)&addr, posix.socklen_t(size_of(addr))) != posix.result(0) {
        fmt.eprintln("Failed to connect to Discord IPC")
        posix.close(discord_socket_fd)
        discord_socket_fd = -1
        return
    }

    handshake_payload := json.Object{
        "v"         = json.Integer(1),
        "client_id" = json.String(discord_client_id),
    }
    if !send_json(discord_socket_fd, .Handshake, handshake_payload) {
        fmt.eprintln("Failed to send handshake")
        posix.close(discord_socket_fd)
        discord_socket_fd = -1
        return
    }

    fmt.println("Connected and handshaken with Discord IPC.")

    discord_ipc_thread = thread.create(discord_ipc_loop)
    thread.start(discord_ipc_thread)
}

now := time.now()
start_ms := now._nsec / 1_000_000
    
set_discord_activity :: proc(state, details, large_image: string) {
    if discord_socket_fd < 0 {
        fmt.eprintln("Not connected to Discord IPC.")
        return
    }

    activity_payload := json.Object{
        "cmd"   = json.String("SET_ACTIVITY"),
        "args"  = json.Object{
            "pid"      = json.Integer(discord_client.pid),
            "activity" = json.Object{
                "state"      = json.String(state),
                "details"    = json.String(details),
                "timestamps" = json.Object{
                    "start" = json.Integer(start_ms),
                },
                "assets"     = json.Object{
                    "large_image" = json.String(large_image),
                },
                "instance" = json.Boolean(true),
                "buttons" = json.Array{
                    json.Object{
                        "label" = json.String("Get Koderum"),
                        "url"   = json.String("https://github.com/valdemar-dev/koderum"),
                    },
                },
            },
        },
        "nonce" = json.String(fmt.tprintf("activity-update-%d", now._nsec)),
    }

    if !send_json(discord_socket_fd, .Frame, activity_payload) {
        return
    }
}

discord :: proc() {
    connect_discord_ipc()
    
    looper :: proc() {
        if discord_socket_fd != -1 {
            for {
                if active_buffer != nil {
                    file := strings.concatenate({ "Editing: ", active_buffer.info.name, })
                    defer delete(file)
                    
                    sb := strings.builder_make()
                    defer strings.builder_destroy(&sb)
                    
                    strings.write_string(&sb, "Line: ")
                    strings.write_int(&sb, buffer_cursor_line+1)
                    strings.write_string(&sb, "/")
                    strings.write_int(&sb, len(active_buffer.lines))
                    strings.write_string(&sb, " | Char: ")
                    strings.write_int(&sb, buffer_cursor_char_index)
                    strings.write_string(&sb, " | Diagnostics: ")
                    strings.write_int(&sb, active_buffer.error_count)
                    
                    line := strings.to_string(sb)
                    
                    set_discord_activity(line, file, "koderum_logo")
                } else {
                    buf : [32]u8
                    
                    fps := strconv.itoa(buf[:], fps)
                    
                    fps_text := strings.concatenate({
                        "Running at ",
                        fps,
                        "fps.",
                    })
                    
                    defer delete(fps_text)
                    
                    set_discord_activity(fps_text, "Not in a file.", "koderum_logo")
                }
                
                time.sleep(time.Second * 1)
            }
        }
    }
    
    thread.run(looper)
}