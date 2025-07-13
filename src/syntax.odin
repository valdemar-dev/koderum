#+feature dynamic-literals
package main

import "core:unicode/utf8"
import "core:os/os2"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:fmt"
import "core:io"
import "core:encoding/json"
import "core:sort"
import ts "../../odin-tree-sitter"
import "core:time"
import "core:thread"
import "core:dynlib"
import "core:net"
import fp "core:path/filepath"
import "core:sync"
import "base:runtime"

tree_mutex : sync.Mutex

@(private="package")
lsp_tokens_mutex : sync.Mutex

@(private="package")
completion_mutex : sync.Mutex

@(private="package")
parser_alert : ^Alert

Language :: struct {
    ts_query_src: cstring,
    ts_language: ^ts.Language,
    ts_colors: map[string]vec4,

    lsp_colors: map[string]vec4,
    lsp_working_dir: string,
    lsp_command: []string,
    lsp_install_command: string,

    // Function to call in case you need to manually set a tokens type.
    override_node_type : proc(
        node_type: ^string,
        node: ts.Node, 
        source: []u8,
        start_point,
        end_point: ^ts.Point,
        tokens: ^[dynamic]Token,
        priority: ^u8,
    ),
    
    // Files to look for to determine the root of a project.
    // tsconfig.json, ols.json, etc.    
    project_root_markets: []string,

    // Where the installed parser is located.
    // Parsers are here: .local/share/koderum/parsers/<PARSER>.
    parser_name: string,

    // Used for when compiling the parser.
    // Example: tree-sitter/tree-sitter-typescript/typescript
    parser_subpath: string,

    // Where to download the parser.
    parser_link: string,

    // Eg. tree_sitter_typescript().
    language_symbol_name: string,
    
    // This colour is used when no token is present.
    filler_color: vec4,
}

LanguageServer :: struct {
    name : string,

    lsp_stdin_w : ^os2.File,
    lsp_stdout_r : ^os2.File,
    lsp_server_pid : int,
    
    token_types : []string,
    token_modifiers : []string,

    completion_trigger_runes : []rune,
    
    ts_parser: ts.Parser, 

    override_node_type: proc(
        node_type: ^string,
        node: ts.Node, 
        source: []u8,
        start_point,
        end_point: ^ts.Point,
        tokens: ^[dynamic]Token,  
        priority: ^u8,
    ),

    language: ^Language,
}

Token :: struct {
    line: i32,
    char:        i32,
    length:      i32,
    color: vec4,
    modifiers:   []string,
    priority: u8,
}

log_unhandled_treesitter_cases := false
lsp_request_id := 10

active_language_server : ^LanguageServer
active_language_servers : map[string]^LanguageServer = {}


languages : map[string]Language = {
/*    ".ts"=Language{
        ts_query_src=ts_ts_query_src,

        ts_colors=ts_ts_colors,
        lsp_colors=ts_lsp_colors,

        lsp_command=[]string{"typescript-language-server", "--stdio", "--log-level", "1"},
        lsp_working_dir="", 
        lsp_install_command="npm install -g typescript-language-server typescript",

        override_node_type=ts_override_node_type,

        parser_name="typescript",
        parser_subpath="typescript",
        parser_link="https://github.com/tree-sitter/tree-sitter-typescript",

        language_symbol_name="tree_sitter_typescript",
        
        filler_color=TOKEN_COLOR_05,
    }, */
    ".odin"=Language{
        ts_query_src=ts_odin_query_src,

        ts_colors=ts_odin_colors,
        lsp_colors=odin_lsp_colors,

        lsp_command=[]string{"ols"},
        lsp_working_dir="/usr/bin/ols",
        lsp_install_command="https://github.com/DanielGavin/ols",

        override_node_type=odin_override_node_type,
        parser_name="odin",
        parser_subpath="",
        parser_link="https://github.com/tree-sitter-grammars/tree-sitter-odin",

        language_symbol_name="tree_sitter_odin",
        
        project_root_markets={"ols.json"},
        
        filler_color=TOKEN_COLOR_05,
    }
}

install_tree_sitter :: proc() -> os2.Error { 
    command : []string = {
        "git",
        "clone",
        "--branch=master",
        "--depth=1",
        "https://github.com/tree-sitter/tree-sitter.git",
        "tree-sitter",
    } 

    error := run_program(
        command, 
        nil,
        data_dir,
    )

    command = {
        "make"
    }

    tree_sitter_dir := strings.concatenate({
        data_dir,
        "/tree-sitter",
    })

    defer delete(tree_sitter_dir)

    error = run_program(
        command,
        nil,
        tree_sitter_dir,
    )

    // Patching weirdness.
    mkdir_dest := strings.concatenate({
        tree_sitter_dir,
        "/lib/include/tree_sitter",
    })
    
    defer delete(mkdir_dest)
    
    command = {
        "mkdir",
        "-p",
        mkdir_dest,
    }

    error = run_program(
        command,
        nil,
        tree_sitter_dir,
    )
    
    header_loc := strings.concatenate({
        tree_sitter_dir,
        "/lib/src/parser.h",
    })
    
    include_path := strings.concatenate({
        tree_sitter_dir,
        "/lib/include/tree_sitter/",
    })
    
    defer delete(include_path)
    defer delete(header_loc)

    when ODIN_OS == .Windows {
        command = {
            "copy",
            header_loc,
            include_path,
        }
    } else {
        command = {
            "cp",
            header_loc,
            include_path,
        }
    }
    
    error = run_program(
        command,
        nil,
        tree_sitter_dir,
    )

    return os2.ERROR_NONE
}

install_parser :: proc(language: ^Language, parser_dir: string) -> os2.Error {
    temp_dir := strings.concatenate({
        data_dir,
        "/tmp",
    })

    defer delete(temp_dir)

    dir_error := os.make_directory(temp_dir, u32(os.File_Mode(0o700)))

    if dir_error != os.ERROR_NONE && os.exists(temp_dir) == false {
        fmt.println(dir_error)
        panic("Failed to create temp directory.")
    }

    defer os.remove_directory(temp_dir)

    command : []string = {
        "git",
        "clone",
        "--depth=1",
        language.parser_link,
        language.parser_name,
    } 

    error := run_program(
        command, 
        nil,
        temp_dir,
    )

    compilation_dir : string
    
    defer delete(compilation_dir)

    when ODIN_OS == .Linux {
        compilation_dir = strings.concatenate({
            temp_dir,
            "/",
            language.parser_name,
            "/",
            language.parser_subpath,
        })
        
        include_path := strings.concatenate({
            "-I",
            data_dir,
            "/tree-sitter/lib/include"
        })
        
        defer delete(include_path)

        command = {
            "cc",
            "-fPIC",
            include_path,
            "-c",
            "src/parser.c",
            "src/scanner.c",
        }
    } else when ODIN_OS == .Darwin {
        compilation_dir = strings.concatenate({
            temp_dir,
            "/",
            language.parser_name,
            "/",
            language.parser_subpath,
        })
        
        include_path := strings.concatenate({
            "-I",
            data_dir,
            "/tree-sitter/lib/include"
        })
        
        defer delete(include_path)

        command = {
            "cc",
            "-fPIC",
            include_path,
            "-c",
            "src/parser.c",
            "src/scanner.c",
        }
    } else when ODIN_OS == .Windows {
        compilation_dir = strings.concatenate({
            temp_dir,
            "\\",
            language.parser_name,
            "\\",
            language.parser_subpath,
        })
        
        include_path := strings.concatenate({
            "-I",
            data_dir,
            "\\tree-sitter\\lib\\include"
        })
        
        defer delete(include_path)
        
        command = {
            "gcc",
            include_path,
            "-c",
            ".\\src\\parser.c",
            ".\\src\\scanner.c",
        }
    }
    

    error = run_program(
        command,
        nil,
        compilation_dir,
    )
    
    when ODIN_OS == .Windows {    
        parsers_dir := strings.concatenate({
            data_dir, "\\parsers",
        })
        
        defer delete(parsers_dir)
    
        parser_dir := strings.concatenate({
            parsers_dir, "\\", language.parser_name,
        })
        
        defer delete(parser_dir)

        command = {
            "cmd.exe",
            "/C",
            "mkdir",
            parser_dir,
        }
    } else {    
        parsers_dir := strings.concatenate({
            data_dir, "/parsers",
        })
        
        defer delete(parsers_dir)
    
        parser_dir := strings.concatenate({
            parsers_dir, "/", language.parser_name,
        })
        
        defer delete(parser_dir)
    
        command = {
            "mkdir",
            "-p",
            parser_dir,
        }
    }

    run_program(
        command,
        nil,
        compilation_dir,
    )

    when ODIN_OS == .Linux {
        dll_path := strings.concatenate({
            parser_dir, "/parser.o",
        })
        
        defer delete(dll_path)
        
        command = {
            "gcc",
            "-shared",
            "-fPIC",
            "-o",
            dll_path,
            "parser.o",
            "scanner.o"
        }
    } else when ODIN_OS == .Darwin {
        dll_path := strings.concatenate({
            parser_dir, "/parser.o",
        })
    
        defer delete(dll_path)
        
        command = {
            "gcc",
            "-shared",
            "-fPIC",
            "-o",
            dll_path,
            "parser.o",
            "scanner.o"
        }
    } else when ODIN_OS == .Windows {
        dll_path := strings.concatenate({
            parser_dir, "\\parser.dll",
        })
        
        defer delete(dll_path)
        
        command = {
            "gcc",
            "-shared",
            "-o",
            dll_path,
            ".\\parser.o",
            ".\\scanner.o",
        }
    }

    error = run_program(
        command,
        nil,
        compilation_dir,
    )
    
    return error 
}

init_parser :: proc(language: ^Language) {
    message := strings.concatenate({
        "The parser for the language ",
        language.parser_name,
        " is initializing.."
    })
    
    defer delete(message)
    
    parser_alert = create_alert(
        "Loading parser..",
        message,
        -1,
        context.allocator,
    )
 
    defer {
        parser_alert^.show_seconds = 5
        parser_alert^.remaining_seconds = 5

        parser_alert = nil
    }
    
    tree_sitter_dir := strings.concatenate({
       data_dir,
       "/tree-sitter",
    })

    defer delete(tree_sitter_dir)

    if os.exists(tree_sitter_dir) == false {
        edit_alert(
            parser_alert,
            "Loading parser..",
            "Installing tree-sitter..",
        )

        error := install_tree_sitter()

        if error != os2.ERROR_NONE {
            edit_alert(
                parser_alert,
                "Error!",
                "Failed to install tree-sitter!",
            )

            parser_alert^.show_seconds = 10
            parser_alert^.remaining_seconds = 10

            return
        } else {
            edit_alert(
                parser_alert,
                "Success!",
                "Tree-sitter was installed!",
            )
        }
    }
    
    parser_dir : string
    
    when ODIN_OS == .Windows {    
        parser_dir = strings.concatenate({
            data_dir,
            "\\parsers\\",
            language.parser_name,
        })
    } else {
        parser_dir = strings.concatenate({
            data_dir,
            "/parsers/",
            language.parser_name,
        })
    }

    defer delete(parser_dir)

    if os.exists(parser_dir) == false {
        edit_alert(
            parser_alert,
            "Installing parser..",
            strings.concatenate({
                "Installing parser for language ", language.parser_name
            }, context.temp_allocator),
        )

        error := install_parser(language, parser_dir)
        
        if error == os2.General_Error.Not_Exist {
            edit_alert(
                parser_alert,
                "Failed to install parser!",
                "Make sure you have installed git and gcc, and that both are available in the system PATH."
            )
            
            return
        }

        if error != os2.ERROR_NONE {
            edit_alert(
                parser_alert,
                "Failed to install parser!",
                strings.concatenate({
                    "Failed to install parser for language ", language.parser_name
                }, context.temp_allocator),
            )

            // panic("Parser could not be installed.")
            return
        } else {
            edit_alert(
                parser_alert,
                "Installed parser!",
                strings.concatenate({
                    "Successfully installed parser for language ", language.parser_name
                }, context.temp_allocator),
            )
        }
    }
    
    parser_path : string
    
    when ODIN_OS == .Linux {
        parser_path = strings.concatenate({
            parser_dir,
            "/parser.o",
        })
    } else when ODIN_OS == .Darwin {
        parser_path = strings.concatenate({
            parser_dir,
            "/parser.o",
        })
    } else when ODIN_OS == .Windows {
        parser_path = strings.concatenate({
            parser_dir,
            "\\parser.dll",
        })
    }
    
    defer delete(parser_path)

    lib, ok := dynlib.load_library(parser_path)
    if !ok {
        fmt.eprintln("Failed to load:", dynlib.last_error())

        fmt.eprintln("Path:", parser_path)
        
        panic("Unrecoverable error.")
    }

    LanguageProc :: proc() -> ts.Language

    ptr, found := dynlib.symbol_address(lib, language.language_symbol_name)

    if !found || ptr == nil {
        fmt.eprintln("Could not load library: ", dynlib.last_error())
        
        fmt.eprintln("Path:", parser_path)

        panic("Unrecoverable error.")
    }

    lang_proc := cast(LanguageProc)ptr

    ts_lang := new(ts.Language)
    ts_lang^ = lang_proc()

    edit_alert(
        parser_alert,
        "Success!",
        strings.concatenate({
            "Parser for language ", language.parser_name, " has been initialized."
        }, context.temp_allocator),
    )

    language.ts_language = ts_lang
}

set_active_language_server :: proc(ext: string) {
    active_language_server = nil
    
    if ext in active_language_servers {
        active_language_server = active_language_servers[ext]
    }

    defer {
        init_message_thread()
    }
    
    exe_path := os2.args[0]
    
    exe_dir := fp.dir(exe_path)
    defer delete(exe_dir)
    
    languages_path := strings.concatenate({
        exe_dir,
        "/languages",
    })
    
    defer delete(languages_path)

    language_servers_list, error := os2.read_directory_by_path(
        languages_path,
        -1, 
        context.allocator
    )
    
    defer delete(language_servers_list)
    
    if error != os2.ERROR_NONE {
        create_alert(
            "Failed to get language servers.",
            "This error is not recoverable.",
            5,
            context.allocator,
        )
        
        return
    }
    
    hit : ^os2.File_Info
    scm_file_path : string
    
    defer delete(scm_file_path)
    
    for &file in language_servers_list {
        ext_name := ext[1:]
    
        file_name := fp.short_stem(file.name)
        
        if ext_name == file_name {
            hit = &file
            
            scm_file_path = strings.concatenate({languages_path, "/", ext_name, ".scm"})
            
            break
        }
    }
    
    if hit == nil {
        return
    }
    
    read_language_from_file(ext, hit.fullpath, scm_file_path)

    init_language_server(ext)
}

get_project_root :: proc(
    file_path: string, 
    target_files: []string
) -> (string, bool) {
    if len(target_files) == 0 {
        return "", false
    }
    
	root := fp.dir(file_path)

	for {
		for target in target_files {
            marker_path := fp.join({root, target})
            
            if os.exists(marker_path) {
                return strings.concatenate({root, "/"}), true
            }
        }
        
        parent := fp.dir(root)
		if parent == root || parent == "" {
            break
		}

		root = parent
	}

	return "", false
}

read_language_from_file :: proc(
    ext: string, 
    language_file_path: string,
    scm_file_path: string,
) {
    bytes, ok := os.read_entire_file_from_filename(language_file_path)
    defer delete(bytes)
    
    if !ok {
        return
    }
    
    value, err := json.parse_string(string(bytes))
    obj,obj_ok := value.(json.Object)
    
    show_malformed_err :: proc(language_file_path: string) {
        create_alert(
            "Malformed language file JSON",
            language_file_path,
            10,
            context.allocator
        )
        
        return
    }
    
    if err != .None || obj_ok == false {
        show_malformed_err(language_file_path)
    }
    
    language : Language
    
    // Parse Colors
    {
        color_map, ok := obj["ts_colors"].(json.Object)
        
        if !ok {
            show_malformed_err(language_file_path)
            
            return
        }
        
        ts_colors : map[string]vec4
        
        for field, color_val in color_map {
            color_index, ok := color_val.(json.Float)
            
            if !ok {
                show_malformed_err(language_file_path)
            
                return
            }
            
            color := color_index_to_color(int(color_index))
            
            if color == nil {
                buf : [4]byte
                
                error_msg := strings.concatenate({
                    "Color with index ",
                    strconv.itoa(buf[:], int(color_index)),
                    " was not found."
                })
                
                create_alert(
                    "Color not found.",
                    error_msg,
                    5,
                    context.allocator,
                )
                
                return
            }
            
            ts_colors[field] = color^
        }
        
        language.ts_colors = ts_colors
    }
    
    // Parse LSP Colors
    {
        color_map, ok := obj["lsp_colors"].(json.Object)
        
        if !ok {
            show_malformed_err(language_file_path)
            
            return
        }
        
        lsp_colors : map[string]vec4
        
        for field, color_val in color_map {
            color_index, ok := color_val.(json.Float)
            
            if !ok {
                show_malformed_err(language_file_path)
            
                return
            }
            
            color := color_index_to_color(int(color_index))
            
            if color == nil {
                buf : [4]byte
                
                error_msg := strings.concatenate({
                    "Color with index ",
                    strconv.itoa(buf[:], int(color_index)),
                    " was not found."
                })
                
                create_alert(
                    "Color not found.",
                    error_msg,
                    5,
                    context.allocator,
                )
                
                return
            }
            
            lsp_colors[field] = color^
        }
        
        language.lsp_colors = lsp_colors
    }
    
    // LSP Command
    {
        lsp_command_arr, ok := obj["lsp_command"].(json.Array)
        
        if !ok {
            show_malformed_err(language_file_path)
            
            return
        }
        
        dyn := make([dynamic]string)
        
        for command_arg in lsp_command_arr {
            string_val, ok := command_arg.(json.String)
            
            if !ok {
                show_malformed_err(language_file_path)
                
                return
            }
            
            append(&dyn, strings.clone(string_val))
        }
        
        language.lsp_command = dyn[:]
    }
    
    // LSP Working Dir
    {
        lsp_working_dir, ok := obj["lsp_working_dir"].(json.String)
        
        if !ok {
            show_malformed_err(language_file_path)
            
            return
        }
        
        language.lsp_working_dir = lsp_working_dir
    }
    
    // LSP Install Command
    {
        lsp_install_command, ok := obj["lsp_install_command"].(json.String)
        
        if !ok {
            show_malformed_err(language_file_path)
            
            return
        }
        
        language.lsp_install_command = lsp_install_command
    }
    
    
    // Parser Name
    {
        parser_name, ok := obj["parser_name"].(json.String)
        
        if !ok {
            show_malformed_err(language_file_path)
            
            return
        }
        
        language.parser_name = parser_name
    }
    
    // Parser Subpath
    {
        parser_subpath, ok := obj["parser_subpath"].(json.String)
        
        if !ok {
            show_malformed_err(language_file_path)
            
            return
        }
        
        language.parser_subpath = parser_subpath
    }
    
    // Parser Link
    {
        parser_link, ok := obj["parser_link"].(json.String)
        
        if !ok {
            show_malformed_err(language_file_path)
            
            return
        }
        
        language.parser_link = parser_link
    }
    
    // Language Symbol Name
    {
        language_symbol_name, ok := obj["language_symbol_name"].(json.String)
        
        if !ok {
            show_malformed_err(language_file_path)
            
            return
        }
        
        language.language_symbol_name = language_symbol_name
    }
    
    // Filler Color
    {
        filler_color, ok := obj["filler_color"].(json.Float)
        
        if !ok {
            show_malformed_err(language_file_path)
            
            return
        }
        
        color := color_index_to_color(int(filler_color))
        
        if color == nil {
            buf : [4]byte
            
            error_msg := strings.concatenate({
                "Color with index ",
                strconv.itoa(buf[:], int(filler_color)),
                " was not found."
            })
            
            create_alert(
                "Color not found.",
                error_msg,
                5,
                context.allocator,
            )
            
            return
        }
        
        language.filler_color = color^
    }
    
    // Get SCM TS Query
    if os.exists(scm_file_path) {
        bytes, ok := os.read_entire_file_from_filename(scm_file_path)
        
        language.ts_query_src = strings.clone_to_cstring(string(bytes[:]))
        
        delete(bytes)
    }
    
    fmt.println(language)
    
    languages[ext] = language
}

init_language_server :: proc(ext: string) {
    language := &languages[ext]

    parser := ts.parser_new()

    init_parser(language)
    
    if language.ts_language == nil {
        fmt.println("Failed to init parser.")

        return
    }

    if !ts.parser_set_language(parser, language.ts_language^) {
        panic("Failed to set parser language to.")
    }
    
    stdin_r, stdin_w, _ := os2.pipe()
    stdout_r, stdout_w, _ := os2.pipe()

    defer os2.close(stdout_w)
    defer os2.close(stdin_r)
    
    dir := fp.dir(active_buffer.file_name)
    defer delete(dir)

    desc := os2.Process_Desc{
        command = language.lsp_command,
        env = nil,
        working_dir = language.lsp_working_dir,
        stdin  = stdin_r,
        stdout = stdout_w,
        stderr = nil,
    }

    process, start_err := os2.process_start(desc)
    
    if start_err == .Not_Exist {
        notification := new(Notification)

        notification^ = Notification{
            title="Server Missing",
            content=strings.concatenate({
                "Please install the LSP Server for ",
                language.parser_name, ".",
            }),
            copy_text=language.lsp_install_command,
        }

        append(&notification_queue, notification)

        return
    }
    
    if start_err != os2.ERROR_NONE {
        fmt.println(start_err)
        panic("Failed to start language server.")
    }

    server := new(LanguageServer)
    server^ = LanguageServer{
        lsp_stdin_w = stdin_w,
        lsp_stdout_r = stdout_r,
        lsp_server_pid = process.pid,
        override_node_type=language.override_node_type,
        ts_parser=parser,
        token_types={},
        token_modifiers={},
        language=language,
        completion_trigger_runes={},
    }

    active_language_server = server
    active_language_servers[ext] = server
    
    directory, ok := get_project_root(active_buffer.file_name, language.project_root_markets)
    
    if !ok {
        directory = cwd
    }
        
    fmt.println(directory)

    msg := initialize_message(process.pid, directory)
    defer delete(msg)

    id := "1"

    send_lsp_message(msg, id, set_capabilities, rawptr(server))
    /*
    msg_2 := did_change_workspace_folders_message(
        directory, directory,
    )
 
    send_lsp_init_message(msg_2, stdin_w)

    defer delete(msg_2)
    */

    set_capabilities :: proc(response: json.Object, data: rawptr) {
        result_obj, _ := response["result"].(json.Object)

        when ODIN_DEBUG {
            fmt.println("Capabilities Object:", response)   
        }

        server := cast(^LanguageServer)data

        capabilities_obj, capabilities_ok := result_obj["capabilities"].(json.Object)

        when ODIN_DEBUG {
            fmt.println("Settings capabilities for LSP..")
        }
 
        completion_provider, completion_provider_ok := capabilities_obj["completionProvider"].(json.Object)

        if (completion_provider_ok) {
            trigger_characters := completion_provider["triggerCharacters"].(json.Array)

            trigger_runes : [dynamic]rune = {}
            for trigger_character in trigger_characters {
                r := utf8.rune_at_pos(trigger_character.(string), 0)

                append(&trigger_runes, r)
            }

            server^.completion_trigger_runes=trigger_runes[:]
        }
       
        provider_obj, provider_ok := capabilities_obj["semanticTokensProvider"].(json.Object)
        
        legend_obj, legend_ok := provider_obj["legend"].(json.Object)

        if legend_ok {
            modifiers_arr, modifiers_ok := legend_obj["tokenModifiers"].(json.Array)
            types_arr := legend_obj["tokenTypes"].(json.Array)
            
            modifiers := value_to_str_array(modifiers_arr)
            types := value_to_str_array(types_arr)

            server^.token_modifiers = modifiers
            server^.token_types = types
        }
            
        when ODIN_DEBUG{
            fmt.println("LSP has been initialized.")
        }
        
        sync.lock(&tree_mutex)

        active_buffer.previous_tree = parse_tree(0, len(active_buffer.lines))
        
        sync.unlock(&tree_mutex)

        do_refresh_buffer_tokens = true
    }
}

lsp_handle_file_open :: proc() {
    set_active_language_server(active_buffer.ext)
    
    if active_language_server == nil {
        return
    }
    
    escaped := escape_json(string(active_buffer.content[:]))
    defer delete(escaped)

    encoded := encode_uri_component(active_buffer.file_name)
    defer delete(encoded)

    uri := strings.concatenate(
        {"file://", encoded}, context.temp_allocator,
    )
    
    language := languages[active_buffer.ext]

    msg := did_open_message(
        uri,
        language.parser_name,
        1,
        escaped,
    )

    defer delete(msg)

    send_lsp_message(msg, "") 
    
    sync.lock(&tree_mutex)

    new_tree := parse_tree(
        0, len(active_buffer.lines)
    )

    ts.tree_delete(active_buffer.previous_tree)
    active_buffer.previous_tree = new_tree
    
    sync.unlock(&tree_mutex)

    do_refresh_buffer_tokens = true
}

decode_modifiers :: proc(bitset: i32, modifiers: []string) -> []string {
    result := make([dynamic]string)
    
    for i in 0..<len(modifiers) {
        if (bitset & (1 << u32(i))) != 0 {
            append(&result, modifiers[i])
        }
    }

    return result[:]
}

decode_semantic_tokens :: proc(data: []i32, token_types: []string, token_modifiers: []string) -> [dynamic]Token {
    tokens := make([dynamic]Token)
    
    line: i32 = 0
    char: i32 = 0

    for i in 0..<len(data) / 5 {
        idx := i * 5
        delta_line := data[idx + 0]
        delta_char := data[idx + 1]
        length := data[idx + 2]
        token_type_index := data[idx + 3]
        token_mod_bitset := data[idx + 4]

        line += delta_line
        
        if delta_line == 0 {
            char += delta_char
        } else {
            char = delta_char
        }

        type := &active_language_server.token_types[token_type_index]

        color := &active_language_server.language.lsp_colors[type^]

        if color == nil {
            when ODIN_DEBUG {
                fmt.println(
                    "Warning: Missing LSP-Token Colour for Node Type",
                    type^, 
                )
            }

            continue
        }

        t := Token{
            line = line,
            char = char,
            length = length,
            color = color^,
            modifiers = decode_modifiers(token_mod_bitset, token_modifiers),
            priority = 0,
        }
        
        append(&tokens, t)
    }

    return tokens
}

set_buffer_tokens :: proc() {
    if active_language_server == nil {
        return
    }
     
    when ODIN_DEBUG {
        start := time.now()
        prev := start
    }
    
    start_version := active_buffer.version 
    
    sync.lock(&tree_mutex)

    new_tree := parse_tree(
        active_buffer.first_drawn_line,
        active_buffer.last_drawn_line,
    )

    ts.tree_delete(active_buffer.previous_tree)
    active_buffer.previous_tree = new_tree
    
    sync.unlock(&tree_mutex)

    {
        when ODIN_DEBUG {
            now := time.now()
            
            fmt.println("Took", time.diff(start, now), "to set single-threaded buffer tokens.")
            
            prev = now
        }
    }    
}

set_buffer_tokens_threaded :: proc() {
    if active_language_server == nil {
        return
    } 
    
    context = runtime.default_context()
    
    do_refresh_buffer_tokens = false
  
    start_version := new(int)
    start_version^ = active_buffer.version

    lsp_request_id += 1 
    
    msg,req_id_string := semantic_tokens_request_message(
        lsp_request_id,
        strings.concatenate({"file://",active_buffer.file_name}, context.temp_allocator),
        0, len(active_buffer.lines)
    )

    defer delete(msg)
    defer delete(req_id_string)

    send_lsp_message(
        msg,
        req_id_string,
        handle_response,
        rawptr(start_version),
    )

    sync.lock(&tree_mutex)
    new_tree := parse_tree(0, len(active_buffer.lines))
    ts.tree_delete(new_tree)
    sync.unlock(&tree_mutex)

    handle_response :: proc(response: json.Object, data: rawptr) {
        context = runtime.default_context()
        
        defer free(data)

        start_version_ptr := (cast(^int)data)

        start_version := (start_version_ptr^)
        
        obj,ok := response["result"].(json.Object)
        
        if !ok {
            return
        }
        
        obj_data,data_ok := obj["data"].(json.Array)
        
        if !data_ok {
            panic("Malformed json in set_buffer_tokens")
        }
        
        lsp_tokens := make([dynamic]i32)
        defer delete(lsp_tokens)

        for value in obj_data {
            append(&lsp_tokens, i32(value.(f64)))
        }

        decoded_tokens := decode_semantic_tokens(
            lsp_tokens[:],
            active_language_server.token_types,
            active_language_server.token_modifiers,  
        )
       
        assert(active_language_server != nil)

        sync.lock(&lsp_tokens_mutex)
        
        set_lsp_tokens(active_buffer, decoded_tokens[:])

        sync.unlock(&lsp_tokens_mutex)
        
        delete(decoded_tokens)
    }
}

notify_server_of_change :: proc(
    buffer: ^Buffer,

    // TS STUFF
    start_byte: int,
    end_byte: int,
    
    // LSP STUFF
    start_line: int,
    start_char: int,
    end_line: int,
    end_char: int,

    new_text: []u8,

    do_update_buffer_content := true,
) {
    constrain_scroll_to_cursor()
    
    new_end_byte := start_byte + len(new_text)

    if do_update_buffer_content {
        append(&active_buffer.undo_stack, BufferChange{
            u32(start_byte),
            u32(end_byte),
            start_line,
            start_char,
            end_line,
            end_char,
            transmute([]u8)(strings.clone(string(buffer.content[start_byte:end_byte]))),
            transmute([]u8)(strings.clone(string(new_text))),
        })

        clear(&active_buffer.redo_stack)

        remove_range(&buffer.content, start_byte, end_byte)
        inject_at(&buffer.content, start_byte, ..new_text)        
    }

    if active_language_server == nil {
        return
    } 
    
    buffer^.version += 1
    
    escaped := escape_json(string(new_text))
    defer delete(escaped)

    msg := text_document_did_change_message(
        strings.concatenate({
            "file://",
            buffer.file_name,
        }, context.temp_allocator),
        buffer.version,
        start_line, start_char, end_line, end_char, escaped,
    )

    defer delete(msg)
    
    _, write_err := os2.write(active_language_server.lsp_stdin_w, transmute([]u8)msg)

    if buffer.previous_tree != nil {        
        edit := ts.Input_Edit{
            u32(start_byte),
            u32(end_byte),
            u32(new_end_byte),
            ts.Point{},
            ts.Point{},
            ts.Point{},
        }
        
        ts.tree_edit(buffer.previous_tree, &edit)
    }
    
    set_buffer_tokens()
    do_refresh_buffer_tokens = true
}

compute_byte_offset :: proc(buffer: ^Buffer, line: int, rune_index: int) -> int {
    byte_offset := 0
    for i in 0..<line {
        byte_offset += len(buffer.lines[i].characters[:])
        byte_offset += 1
    }

    line_chars := buffer.lines[line].characters[:]
    pos := utf8.rune_offset(string(line_chars), rune_index)

    if pos == -1 {
        byte_offset += len(line_chars)
    } else {
        byte_offset += pos
    }

    return byte_offset
}

read_lsp_message :: proc(file: ^os2.File, allocator := context.allocator) -> ([]u8, os2.Error) {
    header_buf: [dynamic]u8
    header_buf.allocator = allocator

    temp: [1]u8
    delimiter := "\r\n\r\n"
    match_len := 0

    for match_len < 4 {
        n, err := os2.read(file, temp[:])
        if err != os2.ERROR_NONE || n != 1 {
            return nil, err
        }

        _, append_err := append(&header_buf, temp[0])
        if append_err != nil {
            return nil, os2.ERROR_NONE
        }

        if temp[0] == delimiter[match_len] {
            match_len += 1
        } else {
            match_len = 0
        }
    }

    header_str := string(header_buf[:])
    content_len := 0
    for line in strings.split_lines(header_str) {
        if strings.starts_with(line, "Content-Length:") {
            suffix := strings.trim(strings.trim_prefix(line, "Content-Length:"), " ")
            content_len = strconv.atoi(suffix)
            break
        }
    }

    if content_len == 0 {
        return nil, os2.ERROR_NONE // malformed
    }

    body_buf: [dynamic]u8
    body_buf.allocator = allocator
    left := content_len

    for left > 0 {
        temp_size := min(left, 1024)
        temp_read: [1024]u8
        n, err := os2.read(file, temp_read[:temp_size])
        if err != os2.ERROR_NONE {
            return nil, err
        }
        if n == 0 {
            break
        }
        _, append_err := append(&body_buf, ..temp_read[:n])
        if append_err != nil {
            return nil, os2.ERROR_NONE
        }
        left -= n
    }

    return body_buf[:], os2.ERROR_NONE
}

attempt_resolve_request :: proc(idx: int) {
    if idx >= len(completion_hits) {
        return
    }

    lsp_request_id += 1

    hit := &completion_hits[idx]

    msg, id := completion_item_resolve_request_message(
        lsp_request_id,
        hit.raw_data,
    )

    defer delete(msg)
    defer delete(id)

    send_lsp_message(
        msg,
        id,
        handle_response,
        hit,
    )

    handle_response :: proc(response: json.Object, data: rawptr) { 
        hit_ptr := cast(^CompletionHit)data

        if hit_ptr == nil {
            return
        }

        result,_ := response["result"].(json.Object)
        data,_ := result["data"].(json.Object)

        detail,_ := result["detail"].(string)

        hit_ptr^.detail = strings.clone(detail)
    }
}

get_autocomplete_hits :: proc(
    line: int,
    character: int,
    trigger_kind: string,
    trigger_character: string,
) {
    if active_language_server == nil {
        return
    }
    
    lsp_request_id += 1
    selected_completion_hit = 0

    msg, req_id_string := completion_request_message(
        lsp_request_id,
        strings.concatenate({
            "file://",
            active_buffer.file_name,
        }, context.temp_allocator),
        line,
        character,
        trigger_kind,
        trigger_character,
    )

    defer delete(msg)
    defer delete(req_id_string)

    defer if trigger_character != "" {
        delete(trigger_character)
    }    

    send_lsp_message(
        msg,
        req_id_string,
        handle_response,
        nil,
    )

    handle_response :: proc(response: json.Object, data: rawptr) {
        result,result_ok := response["result"].(json.Object)
        items,ok := result["items"].(json.Array)

        new_hits := make([dynamic]CompletionHit)

        cur_line := active_buffer.lines[buffer_cursor_line]
        line_string := string(cur_line.characters[:])

        byte_offset := utf8.rune_offset(line_string, buffer_cursor_char_index)
        if byte_offset == -1 {
            byte_offset = len(line_string)
        }

        last_delimiter_byte := 0

        for char, byte in line_string {
            if byte == byte_offset {
                break
            }

            if rune_in_arr(char, delimiter_runes) {
                last_delimiter_byte = byte+1
            }
        }

        completion_filter_token = line_string[last_delimiter_byte:byte_offset]
        for item in items {
            label, label_ok := item.(json.Object)["label"].(string)
            documentation, documentation_ok := item.(json.Object)["documentation"].(string)

            buf, marshal_error := json.marshal(item)
            defer delete(buf)
            if marshal_error != io.Error.None {
                panic("marshalling error")
            }

            hit := CompletionHit{
                label=strings.clone(label),
                raw_data=strings.clone(string(buf)),
            }

            if documentation_ok {
                hit.documentation = strings.clone(documentation)
            }

            if len(completion_filter_token) > 0 {
                if strings.contains(label, completion_filter_token) == false {
                    continue
                }

                if label == completion_filter_token {
                    inject_at(&new_hits, 0, hit)

                    continue
                }
            }

            append(&new_hits, hit)
        }

        for &hit in completion_hits {
            delete(hit.documentation)
            delete(hit.insertText)
            delete(hit.label)
            delete(hit.raw_data)
            delete(hit.detail)
        }
        
        sync.lock(&completion_mutex)
        
        completion_hits = new_hits

        if len(completion_hits) > 0 {
            attempt_resolve_request(selected_completion_hit)
        }

        sync.unlock(&completion_mutex)
    }
}

go_to_definition :: proc() {
    if active_language_server == nil {
        return
    }
    
    lsp_request_id += 1

    msg,id := goto_definition_request_message(
        lsp_request_id,
        strings.concatenate({
            "file://",
            active_buffer.file_name,
        }, context.temp_allocator),
        buffer_cursor_line,
        buffer_cursor_char_index,
    )

    defer delete(msg)
    defer delete(id)

    send_lsp_message(
        msg,
        id,
        handle_response,
        nil,
    )

    handle_response :: proc(response: json.Object, data: rawptr) {
        results,results_ok := response["result"].(json.Array)
        result : json.Object
        
        if results_ok == true {
            if len(results) == 0 do return
            
            result = results[0].(json.Object)
        } else {
            results, results_ok := response["result"].(json.Object)
            
            if !results_ok do return
            
            result = results
        }

        uri, _ := result["uri"].(string)
        range, _ := result["range"].(json.Object)

        start := range["start"].(json.Object)
        line := start["line"].(json.Float)
        char := start["character"].(json.Float)

        url := uri[7:]
        decoded,ok := net.percent_decode(url)

        cached_buffer_index = get_buffer_index(active_buffer)
        cached_buffer_cursor_line = buffer_cursor_line
        cached_buffer_cursor_char_index = buffer_cursor_char_index

        // below is scuffed.
        // here is a short explanation.
        // open_file() kills the update thread
        // we are in the update thread.
        // therefore, run a separate thread.
        PolyData :: struct {
            name: string,
            line: json.Float,
            char: json.Float,
        }

        data := PolyData{
            decoded,
            line,
            char,
        }

        handle_file_open :: proc(data: PolyData) {
            open_file(data.name)

            set_buffer_cursor_pos(
                int(data.line),
                int(data.char),
            )
        }

        thread.run_with_poly_data(data, handle_file_open) 
    }
}

parse_tree :: proc(first_line, last_line: int) -> ts.Tree { 
    if active_language_server == nil {
        return nil
    }

    active_buffer_cstring := strings.clone_to_cstring(string(active_buffer.content[:]))
    defer delete(active_buffer_cstring)

    tree := ts._parser_parse_string(
        active_language_server.ts_parser,
        active_buffer.previous_tree,
        active_buffer_cstring,
        u32(len(active_buffer_cstring))
    )

    if active_buffer.previous_tree == nil {
        error_offset : u32
        error_type : ts.Query_Error

        language := languages[active_buffer.ext]
        
        query := ts._query_new(
            language.ts_language^,
            language.ts_query_src,
            u32(len(language.ts_query_src)),
            &error_offset,
            &error_type,
        )

        if query == nil {
            fmt.println(string(language.ts_query_src)[error_offset:])
            fmt.println(error_type)
            
            create_alert(
                "Failed to query file.",
                "The query string for the tree-sitter parser contains errors.",
                5,
                context.allocator,
            )
            
            active_language_server = nil
            
            return nil
        }
        
        active_buffer.query = query
    }

    set_tokens(first_line, last_line, &tree)
    
    return tree
}

set_tokens :: proc(first_line, last_line: int, tree_ptr: ^ts.Tree) { 
    if tree_ptr == nil {
        return
    }

    tree := tree_ptr^

    cursor := ts.query_cursor_new()
    
    ts.query_cursor_exec(cursor, active_buffer.query, ts.tree_root_node(tree))

    defer ts.query_cursor_delete(cursor)
 
    start_point := ts.Point{
        row=u32(max(first_line, 0)),
        col=0, 
    }
  
    end_point := ts.Point{
        row=u32(max(last_line, 0)),
        col=0,
    }

    ts.query_cursor_set_point_range(cursor, start_point, end_point) 

    match : ts.Query_Match
    capture_index := new(u32)

    defer free(capture_index)
   
    line_number : int = -1
    outer: for ts._query_cursor_next_capture(cursor, &match, capture_index) {
        capture := match.captures[capture_index^]
        predicate_steps_count : u32

        predicate_steps := ts._query_predicates_for_pattern(
            active_buffer.query, 
            u32(match.pattern_index), 
            &predicate_steps_count
        )
       
        for step_index in 0..<predicate_steps_count {
            step := predicate_steps[step_index]
            if step.type == .String {
                value_len : u32
                
                step_value := ts._query_string_value_for_id(
                    active_buffer.query, 
                    step.value_id, 
                    &value_len
                )
            }
        }

        name_len: u32
        name := ts._query_capture_name_for_id(active_buffer.query, capture.index, &name_len)

        node := capture.node
        node_type := string(name)

        start_point := ts.node_start_point(node)
        end_point := ts.node_end_point(node)
        start_byte := ts.node_start_byte(node)
        end_byte := ts.node_end_byte(node)

        start_row := int(start_point.row)
        end_row := int(end_point.row)

        for row in start_row..=end_row {
            if row >= len(active_buffer.lines) {
                break
            }

            line := &active_buffer.lines[row]

            if row > line_number {
                line_number = row
                clear(&line.ts_tokens)
            }

            start_rune := row == start_row ? int(start_point.col) : 0
            end_rune := row == end_row ? int(end_point.col) : len(line.characters)
            
            length := end_rune - start_rune
            if length <= 0 {
                continue
            }

            current_node_type := node_type
            current_priority: u8 

            if active_language_server.override_node_type != nil {
                active_language_server.override_node_type(
                    &current_node_type, node,
                    active_buffer.content[:],
                    &start_point, &end_point,
                    &line.ts_tokens, &current_priority,
                )
            }

            if current_node_type == "SKIP" {
                continue
            }

            color := &active_language_server.language.ts_colors[current_node_type]

            if color == nil {
                continue
            }
            
            if len(line.ts_tokens) > 0 {
                if line.ts_tokens[len(line.ts_tokens)-1].char == i32(start_rune) {
                    resize(&line.ts_tokens, len(line.ts_tokens)-1)
                }
            }

            append(&line.ts_tokens, Token{
                char = i32(start_rune),
                length = i32(length),
                color = color^,
                priority = current_priority,
            })
        }
    }
}

set_lsp_tokens :: proc(buffer: ^Buffer, lsp_tokens: []Token) {
    get_overlapping_token :: proc(tokens: [dynamic]Token, char: i32) -> (t: ^Token, idx: int) {
        for &token, index in tokens {
            if token.char == char {
                return &token, index
            }
        }

        return nil, -1
    }
    
    sort_proc :: proc(token_a, token_b: Token) -> int {
        return int(token_a.char - token_b.char)
    }
    
    for &line in buffer.lines {
        clear(&line.lsp_tokens)
    }

    for &token in lsp_tokens {
        if int(token.line) >= len(buffer.lines) do continue

        line := &buffer.lines[token.line]
        
        append(&line.lsp_tokens, token)
        
        sort.quick_sort_proc(line.lsp_tokens[:], sort_proc)
    }
}

get_node_text :: proc(node: ts.Node, source: []u8) -> string {
    start := ts.node_start_byte(node)
    end := ts.node_end_byte(node)
    
    return string(source[start:end])
}

indent_rule_language_list : map[string]^map[string]IndentRule = {
    ".txt"=&generic_indent_rule_list,
    ".odin"=&generic_indent_rule_list,
    ".glsl"=&generic_indent_rule_list,
    ".c"=&generic_indent_rule_list,
    ".cpp"=&generic_indent_rule_list,
    ".js"=&generic_indent_rule_list,
    ".ts"=&generic_indent_rule_list,
}

generic_indent_rule_list : map[string]IndentRule = {
    "{"=IndentRule{
        type=.FORWARD,
    },

    "("=IndentRule{
        type=.FORWARD,
    },

    "["=IndentRule{
        type=.FORWARD,
    },
}

@(private="package")
is_delimiter_rune :: proc(r: rune) -> bool {
    for delimiter in delimiter_runes {
        if r == delimiter do return true
    }

    return false
}

