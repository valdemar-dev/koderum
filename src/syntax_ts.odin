#+feature dynamic-literals
#+private file
package main

import "core:os/os2"
import "core:fmt"
import "core:os"
import "core:strings"
import fp "core:path/filepath"
import "core:encoding/json"
import "core:text/regex"
import "core:unicode/utf8"

import ts "../../odin-tree-sitter"

import ts_js_bindings "../../odin-tree-sitter/parsers/javascript"
import ts_ts_bindings "../../odin-tree-sitter/parsers/typescript"

ts_colors : map[string]vec4 = {
    "const"=RED,
    "let"=LIGHT_RED,
    
    "return"=PINK,
    "continue"=PINK,
    "break"=PINK,

    "predefined_type"=PURPLE,
    
    "string_fragment"=GREEN,
    "`"=GREEN,
    "\""=GREEN,
    "'"=GREEN,
    "template_string"=GREEN,

    "import"=RED,
    "export"=RED,

    "from"=RED,
    "typeof"=RED, 
    "throw"=RED,
    
    "number"=LIGHT_GREEN,  
    "true"=RED,   
    "false"=RED,
    
    "await"=CYAN,
    "async"=CYAN,
    
    "as"=RED,
    "any"=RED,
    
    "delete"=RED,
    "undefined"=RED,
    
    "--"=GRAY,
    "++"=GRAY,
    ":"=GRAY,
    "+="=GRAY,
    "}"=GRAY,
    "{"=GRAY,
    "."=GRAY,
    "=>"=GRAY,
    "("=GRAY,
    ")"=GRAY,
    "="=GRAY,
    "/"=GRAY,
    ";"=GRAY,
    "["=GRAY,
    "]"=GRAY,
    "+"=GRAY,
    ","=GRAY,
    "${"=GRAY,
    "==="=GRAY,
    "..."=GRAY,
    "!"=GRAY,
    "||"=GRAY,
    ">"=GRAY,
    "<"=GRAY,
    "?."=GRAY,
    "comment"=DARK_GRAY,

    "if"=PINK,
    "else"=PINK,
    "for_in_statement"=PINK,
    "for"=PINK,
    "while"=PINK,
    "with"=CYAN,
    
    "import_specifier"=ORANGE,
    "identifier"=ORANGE,
        
    "true"=BLUE,    
    "false"=BLUE,
    
    
    "regex_flags"=RED,
    "regex_pattern"=YELLOW,
}

ts_lsp_colors := map[string]vec4{
    "type"=CYAN,
    "property"=PURPLE,
    
    "function"=YELLOW,
    "member"=YELLOW,

    "parameter"=ORANGE,
    "namespace"=ORANGE,
    "variable"=ORANGE,
    "interface"=ORANGE,
    "class"=RED,

    "enum"=ORANGE,
    "enumMember"=YELLOW,
}

@(private="package")
init_syntax_typescript :: proc(ext: string, allocator := context.allocator) -> (server: ^LanguageServer, err: os2.Error) {
    parser := ts.parser_new()
    
    if ext == ".js" {
        if !ts.parser_set_language(parser, ts_js_bindings.tree_sitter_javascript()) {
            fmt.println("Failed to set parser language")
            return
        }
    } else {
        if !ts.parser_set_language(parser, ts_ts_bindings.tree_sitter_typescript()) {
            fmt.println("Failed to set parser language")
            return
        }
    }
    
    stdin_r, stdin_w := os2.pipe() or_return
    stdout_r, stdout_w := os2.pipe() or_return
    
    defer os2.close(stdout_w)
    defer os2.close(stdin_r)
    
    dir := fp.dir(active_buffer.file_name)
    defer delete(dir)

    desc := os2.Process_Desc{
        command = []string{"typescript-language-server", "--stdio"},
        env = nil,
        working_dir = dir,
        stdin  = stdin_r,
        stdout = stdout_w,
        stderr = nil,
    }

    process, start_err := os2.process_start(desc)
    if start_err != os2.ERROR_NONE {
        panic("Failed to start TypeScript language server: ")
    }

    msg := initialize_message(process.pid, dir)
    
    when ODIN_DEBUG {
        fmt.println("LSP REQUEST", msg)
    }
    
    _, write_err := os2.write(stdin_w, transmute([]u8)msg)
    if write_err != os2.ERROR_NONE {
        return server,write_err
    }
    
    delete(msg)

    bytes, read_err := read_lsp_message(stdout_r, allocator)
    if read_err != os2.ERROR_NONE {
        return server,read_err
    }
    
    when ODIN_DEBUG {
        fmt.println("LSP RESPONSE", string(bytes))
    }
    
    delete(bytes)
    
    base := fp.base(dir)
    
    msg = did_change_workspace_folders_message(
        strings.concatenate({"file://",dir}), base
    )
    
    when ODIN_DEBUG {
        fmt.println("LSP REQUEST", msg)
    }
    
    _, write_err = os2.write(stdin_w, transmute([]u8)msg)
    if write_err != os2.ERROR_NONE {
        return server,write_err
    }
    
    bytes, read_err = read_lsp_message(stdout_r, allocator)
    defer delete(bytes)
    
    if read_err != os2.ERROR_NONE {
        return server,read_err
    }
    
    parsed,_ := json.parse(bytes)
    
    obj, obj_ok := parsed.(json.Object)
    
    if !obj_ok {
        panic("Received incorrect packet.")
    }
    
    result_obj, result_ok := obj["result"].(json.Object)
    
    if !result_ok {
        panic("Missing result from lsp packet.")
    }
    
    capabilities_obj, capabilities_ok := result_obj["capabilities"].(json.Object)
    
    if !capabilities_ok {
        panic("Missing result from lsp packet.")
    }
    
    provider_obj, provider_ok := capabilities_obj["semanticTokensProvider"].(json.Object)
    
    if !provider_ok {
        panic("Missing semanticTokensProvider from lsp response.")
    }
    
    legend_obj, legend_ok := provider_obj["legend"].(json.Object)
    
    if !provider_ok {
        panic("Missing legend from lsp response.")
    }
    
    modifiers_arr, modifiers_ok := legend_obj["tokenModifiers"].(json.Array)
    types_arr, types_ok := legend_obj["tokenTypes"].(json.Array)
    
    if !modifiers_ok || !types_ok {
        panic("LSP Legend did not contain types or modifiers.")
    }
    
    modifiers := value_to_str_array(modifiers_arr)
    types := value_to_str_array(types_arr)
    
    server = new(LanguageServer)
    server^ = LanguageServer{
        lsp_stdin_w = stdin_w,
        lsp_stdout_r = stdout_r,
        lsp_server_pid = process.pid,
        token_modifiers = modifiers,
        token_types = types,
        ts_parser = parser,
        colors=ts_lsp_colors,
    }
    
    when ODIN_DEBUG{
        fmt.println("TypeScript LSP has been initialized.")
    }
    
    return server,os2.ERROR_NONE
}

@(private="package")
set_buffer_keywords_ts :: proc(tokens: ^[dynamic]Token) {
    active_buffer_cstring := strings.clone_to_cstring(string(active_buffer.content))
    
    tree := ts._parser_parse_string(
        active_language_server.ts_parser,
        active_buffer.previous_tree,
        active_buffer_cstring,
        u32(len(active_buffer_cstring))
    )
    
    active_buffer.previous_tree = tree
    
    if tree == nil {
        fmt.println("Failed to parse source code")
        return
    }
    
    defer delete(active_buffer_cstring)
    
    root_node := ts.tree_root_node(tree)
    node_type := ts.node_type(root_node)
    
    walk_tree(root_node, active_buffer.content, tokens, active_buffer)
}

walk_tree :: proc(node: ts.Node, source: []u8, tokens: ^[dynamic]Token, buffer: ^Buffer) {
    node_type := string(ts.node_type(node))
    
    start_point := ts.node_start_point(node)
    end_point   := ts.node_end_point(node)
    
    if node_type in ts_colors {
        for row in start_point.row..=end_point.row {
            line := buffer.lines[row]
            line_string := utf8.runes_to_string(line.characters)

            start_col := row == start_point.row ? start_point.col : 0
            end_col   := row == end_point.row   ? end_point.col   : u32(len(line_string))

            start_char := byte_offset_to_rune_index(line_string, int(start_col))
            end_char   := byte_offset_to_rune_index(line_string, int(end_col))

            length := end_char - start_char
            if length <= 0 {
                continue
            }

            priority : u8 = 0
        
            if node_type == "${" {
                priority += 1
            }

            color := ts_colors[node_type]

            append(tokens, Token{
                char     = i32(start_char),
                line     = i32(row),
                length   = i32(length),
                color    = color,
                priority = priority,
            })
        }
    } else {
        when ODIN_DEBUG {
            start := ts.node_start_byte(node)
            end := ts.node_end_byte(node)
            fmt.println("UNHANDLED:", node_type, "Value:", string(source[start:end]))
        }
    }
    
    child_count := ts.node_child_count(node)
    for i in 0..<child_count {
        child := ts.node_child(node, i)
        walk_tree(child, source, tokens, buffer)
    }
}
