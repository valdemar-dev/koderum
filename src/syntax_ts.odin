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

ts_ts_colors : map[string]vec4 = {
    // FUNCTIONS
    "arrow_function_name"=YELLOW,
    "method_call" = YELLOW,
    "function_call" = YELLOW,
    "function_name" = YELLOW,
        
    "const"=RED,
    "let"=LIGHT_RED,
    "function"=LIGHT_RED,
    
    // make code go somewhere else
    "return"=PINK,
    "continue"=PINK,
    "break"=PINK,
    
    // BUILT IN TYPES
    "object_type"=PURPLE,
    "string_type"=GREEN,
    "boolean_type"=BLUE,
    "common_type"=CYAN,
    "number_type"=LIGHT_GREEN,
    
    // NUMBERS
    "number"=LIGHT_GREEN,
    
    // STRINGS
    "string_fragment"=GREEN,
    "`"=GREEN,
    "\""=GREEN,
    "'"=GREEN,
    //"template_string"=GREEN,

    // import export
    "import"=RED,
    "export"=RED,
    
    "from"=RED,
    "typeof"=RED,
    "throw"=RED,
    
    // async
    "await"=CYAN,
    "async"=CYAN,
    
    // casting
    "as"=RED,
    "any"=RED,
    
    // spookies
    "delete"=RED,
    "undefined"=RED,
    
    // make it gray
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
    "|"=GRAY,
    "comment"=DARK_GRAY,

    // logical keywords
    "if"=PINK,
    "else"=PINK,
    "in"=PINK,
    "for"=PINK,
    "of"=PINK,
    "while"=PINK,
    "with"=PINK,
    "switch"=PINK,
    "case"=PINK,
    
    "import_specifier"=ORANGE,

    "variable_name"=ORANGE,    
    
    "true"=BLUE,    
    "false"=BLUE,
    
    "regex_flags"=RED,
    "regex_pattern"=YELLOW,
    
    "property_identifier"=LIGHT_ORANGE,
    
    "parameter_name"=LIGHT_ORANGE,
    
    "identifier"=ORANGE,
}

ts_lsp_colors := map[string]vec4{
    "type"=CYAN,
    "property"=PURPLE,
    
    "function"=YELLOW,
    "member"=YELLOW,

    "parameter"=LIGHT_ORANGE,
    "namespace"=PURPLE,
    
    // "variable"=ORANGE,
    
    "interface"=CYAN,
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
        fmt.println(start_err)
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
        ts_colors=ts_ts_colors,
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
    
    if active_buffer.previous_tree != nil {    
        changes := new(u32)
    
        changes_array := ts._tree_get_changed_ranges(active_buffer.previous_tree, tree, changes)
        
        fmt.println(changes_array)
    }
    
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

@(private="package")
override_node_type_ts :: proc(
    node_type: ^string,
    node: ts.Node, 
    source: []u8,
    start_point,
    end_point: ^ts.Point,
) {
    if node_type^ == "identifier" || node_type^ == "property_identifier" {
        parent := ts.node_parent(node)
        if ts.node_is_null(parent) do return

        parent_type := string(ts.node_type(parent))
    
        switch parent_type {
        case "function_declaration":
            node_type^ = "function_name"

        case "variable_declarator":       
            if value_node, found := get_value_node(parent); found {
                node_type^ = string(ts.node_type(value_node))
            
                if node_type^ == "arrow_function" {
                    node_type^ = "arrow_function_name"
                } else {
                    node_type^ = "variable_name"
                }
            }

        case "method_definition":
            node_type^ = "method_name"

        case "formal_parameters", "parameter", "required_parameter":
            node_type^ = "parameter_name"

        case "member_expression":
            if field_name := ts.node_field_name_for_child(parent, 1); field_name != nil {
                if field_name == "property" && ts.node_eq(node, ts.node_child(parent, 1)) {
                    node_type^ = "method_name"
                } else if field_name == "object" {
                    node_type^ = "object_property"
                }
            }
        }
        return
    }
    
    if node_type^ == "call_expression" || node_type^ == "function_expression" {
        function_node := ts.node_child_by_field_name(node, "function")
        if !ts.node_is_null(function_node) {
            if string(ts.node_type(function_node)) == "member_expression" {
                property_node := ts.node_child_by_field_name(function_node, "property")
                if !ts.node_is_null(property_node) {
                    start_point^ = ts.node_start_point(property_node)
                    end_point^ = ts.node_end_point(property_node)
                    node_type^ = "method_call"
                }
            } else {
                start_point^ = ts.node_start_point(function_node)
                end_point^ = ts.node_end_point(function_node)
                node_type^ = "function_call"
            }
        }
        return
    }

    switch node_type^ {
    case "type_identifier":
        node_type^ = "common_type"

    case "predefined_type":
        type_name := get_node_text(node, source)
        node_type^ = strings.concatenate({type_name, "_type"})
    }
}

get_value_node :: proc(parent: ts.Node) -> (ts.Node, bool) {
    child_count := ts.node_child_count(parent)
    for i: u32 = 0; i < child_count; i += 1 {
        if field_name := ts.node_field_name_for_child(parent, i); field_name != nil {
            if field_name == "value" {
                return ts.node_child(parent, i), true
            }
        }
    }
    return {}, false
}
