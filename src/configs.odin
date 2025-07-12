#+feature dynamic-literals
package main

import "core:os"
import "core:strings"
import "core:strconv"
import "core:fmt"
import "core:math"
import fp "core:path/filepath"
import "core:unicode/utf8"
import "core:dynlib"

font_base_px : f32

small_text_scale : f32
normal_text_scale : f32
large_text_scale : f32
buffer_text_scale : f32
line_thickness_em : f32
line_count_padding_em : f32
cursor_edge_padding_em : f32
ui_scale : f32

BG_MAIN_00 : vec4
BG_MAIN_05 : vec4
BG_MAIN_10 : vec4
BG_MAIN_20 : vec4
BG_MAIN_30 : vec4
BG_MAIN_40 : vec4
BG_MAIN_50 : vec4

TEXT_MAIN : vec4
TEXT_DARKER : vec4
TEXT_DARKEST : vec4
TEXT_ERROR : vec4

TOKEN_COLOR_00 : vec4
TOKEN_COLOR_01 : vec4
TOKEN_COLOR_02 : vec4
TOKEN_COLOR_03 : vec4
TOKEN_COLOR_04 : vec4
TOKEN_COLOR_05 : vec4
TOKEN_COLOR_06 : vec4
TOKEN_COLOR_07 : vec4
TOKEN_COLOR_08 : vec4
TOKEN_COLOR_09 : vec4
TOKEN_COLOR_10 : vec4
TOKEN_COLOR_11 : vec4
TOKEN_COLOR_12 : vec4
TOKEN_COLOR_13 : vec4
TOKEN_COLOR_14 : vec4

do_highlight_long_lines : bool
long_line_required_characters : int
do_draw_line_count : bool
do_highlight_current_line : bool
differentiate_tab_and_spaces : bool
do_highlight_indents : bool

tab_spaces : int

default_cwd : string

program_dir : string

text_highlight_color : vec4 = TEXT_MAIN
text_highlight_bg : vec4 = BG_MAIN_40
delimiter_runes : []rune = {}

search_ignored_dirs : [dynamic]string

do_constrain_cursor_to_scroll : bool = false

config_dir : string
init_config :: proc() -> []u8 {
    home := os.get_env("HOME")

    defer delete(home)

    path : string
    when ODIN_OS == .Linux {
        path = strings.concatenate({ home, "/.config/koderum" })
    } else when ODIN_OS == .Windows {
        appdata := os.get_env("APPDATA")
        
        path = strings.concatenate({ appdata, "/koderum", })
        
        delete(appdata)
    } else when ODIN_OS == .Darwin {
        path = strings.concatenate({
            home, "/Library/Application Support/koderum"
        })
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
        appdata := os.get_env("APPDATA")
        
        path = strings.concatenate({ appdata, "\\koderum", })
        
        delete(appdata)
    } else when ODIN_OS == .Darwin {
        path = strings.concatenate({
            home, "/Library/Application Support/koderum"
        })
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
    case "cursor_edge_padding_em":
        cursor_edge_padding_em = f32(strconv.atof(value))
    case "font":
        append(&font_list, strings.clone(value))
    case "font_base_px":
        font_size := strconv.atof(value)
        font_base_px = f32(font_size)
    case "small_text_scale":
        font_size := strconv.atof(value)
        small_text_scale = f32(font_size)
    case "large_text_scale":
        font_size := strconv.atof(value)
        large_text_scale = f32(font_size)
    case "normal_text_scale":
        font_size := strconv.atof(value)
        normal_text_scale = f32(font_size)
    case "buffer_text_scale":
        font_size := strconv.atof(value)
        buffer_text_scale = f32(font_size)
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
    case "line_thickness_em":
        line_thickness_em = f32(strconv.atof(value))
        fmt.println(value, line_thickness_em, font_base_px, line_thickness_em * font_base_px)
    case "line_count_padding_em":
        line_count_padding_em = f32(strconv.atof(value))
    case "ui_scale":
        ui_scale = f32(strconv.atoi(value))
    case "always_loaded_characters":
        chars := strings.split(value, "")

        for char in chars {
            r := utf8.string_to_runes(char)
            
            big_text := math.round_f32(font_base_px * large_text_scale)
            small_text := math.round_f32(font_base_px * small_text_scale)
            normal_text := math.round_f32(font_base_px * normal_text_scale)
            buffer_text := math.round_f32(font_base_px * buffer_text_scale)
            
            get_char(buffer_text, u64(r[0]))
            get_char(big_text, u64(r[0]))
            get_char(small_text, u64(r[0]))
            get_char(normal_text, u64(r[0]))

            delete(r)
        }

        delete(chars)
    case "search_ignored_dir":
        append(&search_ignored_dirs, strings.clone(value))
    case "delimiter_runes":
        delimiter_runes = utf8.string_to_runes(value)
    case "do_constrain_cursor_to_scroll":
        do_constrain_cursor_to_scroll = (value == "true")    
    case "bg_main_00":
        BG_MAIN_00 = hex_string_to_vec4(value)
    case "bg_main_05":
        BG_MAIN_05 = hex_string_to_vec4(value)
    case "bg_main_10":
        BG_MAIN_10 = hex_string_to_vec4(value)
    case "bg_main_20":
        BG_MAIN_20 = hex_string_to_vec4(value)
    case "bg_main_30":
        BG_MAIN_30 = hex_string_to_vec4(value)
    case "bg_main_40":
        BG_MAIN_40 = hex_string_to_vec4(value)
    case "bg_main_50":
        BG_MAIN_50 = hex_string_to_vec4(value)
    case "text_main":
        TEXT_MAIN = hex_string_to_vec4(value)    
    case "text_darker":
        TEXT_DARKER = hex_string_to_vec4(value)
    case "text_darkest":
        TEXT_DARKEST = hex_string_to_vec4(value)
    case "text_error":
        TEXT_ERROR = hex_string_to_vec4(value)
    case "token_color_00":
        TOKEN_COLOR_00 = hex_string_to_vec4(value)
    case "token_color_01":
        TOKEN_COLOR_01 = hex_string_to_vec4(value)
    case "token_color_02":
        TOKEN_COLOR_02 = hex_string_to_vec4(value)
    case "token_color_03":
        TOKEN_COLOR_03 = hex_string_to_vec4(value)
    case "token_color_04":
        TOKEN_COLOR_04 = hex_string_to_vec4(value)
    case "token_color_05":
        TOKEN_COLOR_05 = hex_string_to_vec4(value)
    case "token_color_06":
        TOKEN_COLOR_06 = hex_string_to_vec4(value)
    case "token_color_07":
        TOKEN_COLOR_07 = hex_string_to_vec4(value)
    case "token_color_08":
        TOKEN_COLOR_08 = hex_string_to_vec4(value)
    case "token_color_09":
        TOKEN_COLOR_09 = hex_string_to_vec4(value)
    case "token_color_10":
        TOKEN_COLOR_10 = hex_string_to_vec4(value)
    case "token_color_11":
        TOKEN_COLOR_11 = hex_string_to_vec4(value)
    case "token_color_12":
        TOKEN_COLOR_13 = hex_string_to_vec4(value)
    case "token_color_13":
        TOKEN_COLOR_14 = hex_string_to_vec4(value)
    case "token_color_14":
        TOKEN_COLOR_14 = hex_string_to_vec4(value)
    case:
        fmt.eprintln("Unknown option,", option_name)
    }
}

