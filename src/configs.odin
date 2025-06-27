#+feature dynamic-literals
package main

import "core:os"
import "core:strings"
import "core:strconv"
import "core:fmt"
import fp "core:path/filepath"
import "core:unicode/utf8"
import "core:dynlib"

tab_spaces : int
long_line_required_characters : int

do_draw_line_count : bool
do_highlight_long_lines : bool
do_highlight_indents : bool
differentiate_tab_and_spaces : bool
do_highlight_current_line : bool

default_cwd : string

cursor_edge_padding : f32
buffer_font_size : f32
ui_bigger_font_size : f32
ui_general_font_size : f32
ui_smaller_font_size : f32

program_dir : string

text_highlight_color : vec4 = TEXT_MAIN

text_highlight_bg : vec4 = BG_MAIN_40
//text_highlight_bg : vec4 = vec4{1,1,1,1}

delimiter_runes : []rune = {}

general_line_thickness_px : f32
line_count_padding_px : f32

search_ignored_dirs : [dynamic]string

ui_scale : f32

do_constrain_cursor_to_scroll : bool = false

config_dir : string
init_config :: proc() -> []u8 {
    home := os.get_env("HOME")

    defer delete(home)

    path : string
    when ODIN_OS == .Linux {
        path = strings.concatenate({ home, "/.config/koderum" })
    } else when ODIN_OS == .Windows {
        path = strings.concatenate({ home, "C:/Users/<user>/AppData/Roaming/koderum" })
    }

    config_dir = path

    if os.exists(path) == false {
        fmt.println("WARNING: Creating default directory.", path)
        error := os.make_directory(path, u32(os.File_Mode(0o700)))

        if error != os.ERROR_NONE {
            fmt.println(error)

            panic("Failed to create default directory.")
        }
    }

    config_location := strings.concatenate({
        path,
        "/options.conf",
    })

    defer delete(config_location)

    if os.exists(config_location) == false {
        fmt.println("WARNING: options.conf was not found. It will instead be created.")
        init_default_config(path)
    }

    bytes, ok := os.read_entire_file_from_filename(
        config_location,
    )

    if !ok {
        fmt.println("Failed to open custom config file.", config_location)
        panic("Unrecoverable error.")
    }

    delete(path)

    return bytes
}

data_dir : string
init_local :: proc () {
    home := os.get_env("HOME")

    defer delete(home)

    path : string
    when ODIN_OS == .Linux {
        path = strings.concatenate({ home, "/.local/share/koderum" })
    } else when ODIN_OS == .Windows {
        path = strings.concatenate({ home, "C:/Users/<user>/AppData/Local/koderum" })
    }

    data_dir = path

    if os.exists(path) == true {
        return
    }

    fmt.println("WARNING: Creating default data directory.", path)
    error := os.make_directory(path, u32(os.File_Mode(0o700)))

    if error != os.ERROR_NONE {
        fmt.println(error)

        panic("Failed to create default data directory.")
    }
}

init_default_config :: proc(default_config_dir: string) {
    exe_path := os.args[0]

    program_dir = fp.dir(exe_path)

    default_config_file := strings.concatenate({
        program_dir,
        "/config/options.conf.example",
    })

    defer delete(default_config_file)

    bytes, ok := os.read_entire_file_from_filename(default_config_file)
    defer delete(bytes)

    if !ok {
        panic("Failed to open default config file.")
    }

    config_file_path := strings.concatenate({
        default_config_dir,
        "/options.conf",
    })

    success := os.write_entire_file(config_file_path, bytes)

    if !success {
        fmt.println("Failed to write configs to options.conf")
    } else {
        fmt.println("Successfully created new options.conf file.")
    }
}

load_configs :: proc() {
    init_local()

    bytes := init_config()

    data_string := string(bytes)

    lines : []string
    when ODIN_OS == .Windows {
        lines = strings.split(data_string, "\r\n")
    }

    when ODIN_OS == .Linux {
        lines = strings.split(data_string, "\n")
    }

    category : string
    values : []string

    for line, index in lines {
        if len(line) == 0 {
            continue
        }

        start_char := line[0]
        end_char : u8

        when ODIN_OS == .Windows {
            test_end := line[len(line)-1]

            if rune(test_end) == '\r' {
                end_char = line[clamp(len(line)-2,0,len(line)-1)]
            } else {
                end_char = test_end
            }
        }

        when ODIN_OS == .Linux {
            end_char = line[len(line)-1]
        }

        if start_char == '[' && end_char == ']' {
            category = line[1:len(line)-1]

            continue
        }

        values := strings.split(line, " = ")

        when ODIN_DEBUG {
            fmt.println("Loading option:", values)
        }

        set_option(values)

        delete(values)
    }

    delete(bytes)
    delete(lines)
}

//TODO: Megajank omegalul
set_option :: proc(options: []string) {
    if len(options) < 2 {
        fmt.eprintf("option,", options, "is improper, must be at least len 2.")

        panic("unrecoverable error.")
    }

    option_name := options[0]

    value := options[1]

    switch option_name {
    case "do_highlight_long_lines":
        do_highlight_long_lines = value == "true"
    case "long_line_required_characters":
        long_line_required_characters = strconv.atoi(value)
    case "do_draw_line_count":
        do_draw_line_count = value == "true"
    case "differentiate_tab_and_spaces":
        differentiate_tab_and_spaces = value == "true"
    case "tab_spaces":
        tab_spaces = strconv.atoi(value)
    case "cursor_edge_padding":
        cursor_edge_padding = f32(strconv.atof(value))
    case "font":
        append(&font_list, strings.clone(value))
    case "ui_general_font_size":
        font_size := strconv.atof(value)
        ui_general_font_size = f32(font_size)
    case "ui_smaller_font_size":
        font_size := strconv.atof(value)
        ui_smaller_font_size = f32(font_size)
    case "ui_bigger_font_size":
        font_size := strconv.atof(value)
        ui_bigger_font_size = f32(font_size)
    case "buffer_font_size":
        font_size := strconv.atof(value)
        buffer_font_size = f32(font_size)
    case "do_highlight_indents":
        do_highlight_indents = value == "true"
    case "default_cwd":
        default_cwd = strings.clone(value)
    case "text_highlight_color":
        text_highlight_color = hex_string_to_vec4(value)
    case "text_highlight_bg":
        text_highlight_bg = hex_string_to_vec4(value)
    case "do_highlight_current_line":
        do_highlight_current_line = value == "true" 
    case "general_line_thickness_px":
        general_line_thickness_px = f32(strconv.atoi(value))
    case "line_count_padding_px":
        line_count_padding_px = f32(strconv.atoi(value))
    case "ui_scale":
        ui_scale = f32(strconv.atoi(value))
    case "always_loaded_characters":
        chars := strings.split(value, "")

        for char in chars {
            r := utf8.string_to_runes(char)

            get_char(buffer_font_size, u64(r[0]))
            get_char(ui_general_font_size, u64(r[0]))
            get_char(ui_smaller_font_size, u64(r[0]))
            get_char(ui_bigger_font_size, u64(r[0]))

            delete(r)
        }

        delete(chars)
    case "search_ignored_dir":
        append(&search_ignored_dirs, strings.clone(value))
    case "delimiter_runes":
        delimiter_runes = utf8.string_to_runes(value)
    case "do_constrain_cursor_to_scroll":
        do_constrain_cursor_to_scroll = (value == "true")
    case:
        fmt.eprintln("Unknown option,", option_name)
    }
}

