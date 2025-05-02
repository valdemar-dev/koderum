#+feature dynamic-literals
package main

import "core:os"
import "core:strings"
import "core:strconv"
import "core:fmt"

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

load_configs :: proc() {
    config_file := "./config/options.conf"

    bytes, ok := os.read_entire_file_from_filename(config_file)

    if !ok {
        concat := strings.concatenate({
            "Failed to open config file,",   
            config_file
        })

        panic(concat)
    }

    data_string := string(bytes)

    lines : []string
    when ODIN_OS == .Windows {
        lines = strings.split(data_string, "\r\n")
    }

    when ODIN_OS == .Linux {
        lines = strings.split(data_string, "\n")
    }

    category : string

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

        trimmed,_ := strings.replace_all(line, " ", "")
        values := strings.split(trimmed, "=")

        when ODIN_DEBUG {
            fmt.println("Loading option:", values)
        }

        set_option(values)
    }
}

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
    case "do_highlight_current_line":
        do_highlight_current_line = value == "true"
    case "differentiate_tab_and_spaces":
        differentiate_tab_and_spaces = value == "true"
    case "tab_spaces":
        tab_spaces = strconv.atoi(value)
    case "cursor_edge_padding":
        cursor_edge_padding := f32(strconv.atof(value))
    case "font":
        append(&font_list, value)
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
        default_cwd = value
    case:
        fmt.eprintln("Unknown option,", option_name)
    }
}

