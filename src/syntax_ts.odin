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
import "core:sort"

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
    
    parsed,_ := json.parse(bytes, json.Specification.JSON, false, context.temp_allocator)
    defer delete(parsed.(json.Object))
        
    obj, obj_ok := parsed.(json.Object)
    
    if !obj_ok {
        panic("Received incorrect packet.")
    }
    
    result_obj, result_ok := obj["result"].(json.Object)
    defer delete(result_obj)
        
    if !result_ok {
        panic("Missing result from lsp packet.")
    }
    
    capabilities_obj, capabilities_ok := result_obj["capabilities"].(json.Object)
    defer delete(capabilities_obj)
    
    if !capabilities_ok {
        panic("Missing result from lsp packet.")
    }
    
    provider_obj, provider_ok := capabilities_obj["semanticTokensProvider"].(json.Object)
    defer delete(provider_obj)
    
    if !provider_ok {
        panic("Missing semanticTokensProvider from lsp response.")
    }
    
    legend_obj, legend_ok := provider_obj["legend"].(json.Object)
    defer delete(legend_obj)
        
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
    
    defer delete(modifiers)
    defer delete(types)
    
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

query_src : cstring = `
    ; Types
    ; Javascript
    ; Variables
    ;-----------
    (identifier) @variable
    
    ; Properties
    ;-----------
    (property_identifier) @variable.member
    
    (shorthand_property_identifier) @variable.member
    
    (private_property_identifier) @variable.member
    
    (object_pattern
      (shorthand_property_identifier_pattern) @variable)
    
    (object_pattern
      (object_assignment_pattern
        (shorthand_property_identifier_pattern) @variable))
    
    ; Special identifiers
    ;--------------------
    ((identifier) @type
      (#lua-match? @type "^[A-Z]"))
    
    ((identifier) @constant
      (#lua-match? @constant "^_*[A-Z][A-Z%d_]*$"))
    
    ((shorthand_property_identifier) @constant
      (#lua-match? @constant "^_*[A-Z][A-Z%d_]*$"))
    
    ((identifier) @variable.builtin
      (#any-of? @variable.builtin "arguments" "module" "console" "window" "document"))
    
    ((identifier) @type.builtin
      (#any-of? @type.builtin
        "Object" "Function" "Boolean" "Symbol" "Number" "Math" "Date" "String" "RegExp" "Map" "Set"
        "WeakMap" "WeakSet" "Promise" "Array" "Int8Array" "Uint8Array" "Uint8ClampedArray" "Int16Array"
        "Uint16Array" "Int32Array" "Uint32Array" "Float32Array" "Float64Array" "ArrayBuffer" "DataView"
        "Error" "EvalError" "InternalError" "RangeError" "ReferenceError" "SyntaxError" "TypeError"
        "URIError"))
    
    (statement_identifier) @label
    
    ; Function and method definitions
    ;--------------------------------
    (function_expression
      name: (identifier) @function)
    
    (function_declaration
      name: (identifier) @function)
    
    (generator_function
      name: (identifier) @function)
    
    (generator_function_declaration
      name: (identifier) @function)
    
    (method_definition
      name: [
        (property_identifier)
        (private_property_identifier)
      ] @function.method)
    
    (method_definition
      name: (property_identifier) @constructor
      (#eq? @constructor "constructor"))
    
    (pair
      key: (property_identifier) @function.method
      value: (function_expression))
    
    (pair
      key: (property_identifier) @function.method
      value: (arrow_function))
    
    (assignment_expression
      left: (member_expression
        property: (property_identifier) @function.method)
      right: (arrow_function))
    
    (assignment_expression
      left: (member_expression
        property: (property_identifier) @function.method)
      right: (function_expression))
    
    (variable_declarator
      name: (identifier) @function
      value: (arrow_function))
    
    (variable_declarator
      name: (identifier) @function
      value: (function_expression))
    
    (assignment_expression
      left: (identifier) @function
      right: (arrow_function))
    
    (assignment_expression
      left: (identifier) @function
      right: (function_expression))
    
    ; Function and method calls
    ;--------------------------
    (call_expression
      function: (identifier) @function.call)
    
    (call_expression
      function: (member_expression
        property: [
          (property_identifier)
          (private_property_identifier)
        ] @function.method.call))
    
    (call_expression
      function: (await_expression
        (identifier) @function.call))
    
    (call_expression
      function: (await_expression
        (member_expression
          property: [
            (property_identifier)
            (private_property_identifier)
          ] @function.method.call)))
    
    ; Builtins
    ;---------
    ((identifier) @module.builtin
      (#eq? @module.builtin "Intl"))
    
    ((identifier) @function.builtin
      (#any-of? @function.builtin
        "eval" "isFinite" "isNaN" "parseFloat" "parseInt" "decodeURI" "decodeURIComponent" "encodeURI"
        "encodeURIComponent" "require"))
    
    ; Constructor
    ;------------
    (new_expression
      constructor: (identifier) @constructor)
    
    ; Decorators
    ;----------
    (decorator
      "@" @attribute
      (identifier) @attribute)
    
    (decorator
      "@" @attribute
      (call_expression
        (identifier) @attribute))
    
    (decorator
      "@" @attribute
      (member_expression
        (property_identifier) @attribute))
    
    (decorator
      "@" @attribute
      (call_expression
        (member_expression
          (property_identifier) @attribute)))
    
    ; Literals
    ;---------
    [
      (this)
      (super)
    ] @variable.builtin
    
    ((identifier) @variable.builtin
      (#eq? @variable.builtin "self"))
    
    [
      (true)
      (false)
    ] @boolean
    
    [
      (null)
      (undefined)
    ] @constant.builtin
    
    [
      (comment)
      (html_comment)
    ] @comment @spell
    
    ((comment) @comment.documentation
      (#lua-match? @comment.documentation "^/[*][*][^*].*[*]/$"))
    
    (hash_bang_line) @keyword.directive
    
    ((string_fragment) @keyword.directive
      (#eq? @keyword.directive "use strict"))
    
    (string) @string
    
    (template_string) @string
    
    (escape_sequence) @string.escape
    
    (regex_pattern) @string.regexp
    
    (regex_flags) @character.special
    
    (regex
      "/" @punctuation.bracket) ; Regex delimiters
    
    (number) @number
    
    ((identifier) @number
      (#any-of? @number "NaN" "Infinity"))
    
    ; Punctuation
    ;------------
    [
      ";"
      "."
      ","
      ":"
    ] @punctuation.delimiter
    
    [
      "--"
      "-"
      "-="
      "&&"
      "+"
      "++"
      "+="
      "&="
      "/="
      "**="
      "<<="
      "<"
      "<="
      "<<"
      "="
      "=="
      "==="
      "!="
      "!=="
      "=>"
      ">"
      ">="
      ">>"
      "||"
      "%"
      "%="
      "*"
      "**"
      ">>>"
      "&"
      "|"
      "^"
      "??"
      "*="
      ">>="
      ">>>="
      "^="
      "|="
      "&&="
      "||="
      "??="
      "..."
    ] @operator
    
    (binary_expression
      "/" @operator)
    
    (ternary_expression
      [
        "?"
        ":"
      ] @keyword.conditional.ternary)
    
    (unary_expression
      [
        "!"
        "~"
        "-"
        "+"
      ] @operator)
    
    (unary_expression
      [
        "delete"
        "void"
      ] @keyword.operator)
    
    [
      "("
      ")"
      "["
      "]"
      "{"
      "}"
    ] @punctuation.bracket
    
    (template_substitution
      [
        "${"
        "}"
      ] @punctuation.special) @none
    
    ; Imports
    ;----------
    (namespace_import
      "*" @character.special
      (identifier) @module)
    
    (namespace_export
      "*" @character.special
      (identifier) @module)
    
    (export_statement
      "*" @character.special)
    
    ; Keywords
    ;----------
    [
      "if"
      "else"
      "switch"
      "case"
    ] @keyword.conditional
    
    [
      "import"
      "from"
      "as"
      "export"
    ] @keyword.import
    
    [
      "for"
      "of"
      "do"
      "while"
      "continue"
    ] @keyword.repeat
    
    [
      "break"
      "const"
      "debugger"
      "extends"
      "get"
      "let"
      "set"
      "static"
      "target"
      "var"
      "with"
    ] @keyword
    
    "class" @keyword.type
    
    [
      "async"
      "await"
    ] @keyword.coroutine
    
    [
      "return"
      "yield"
    ] @keyword.return
    
    "function" @keyword.function
    
    [
      "new"
      "delete"
      "in"
      "instanceof"
      "typeof"
    ] @keyword.operator
    
    [
      "throw"
      "try"
      "catch"
      "finally"
    ] @keyword.exception
    
    (export_statement
      "default" @keyword)
    
    (switch_default
      "default" @keyword.conditional)
`

@(private="package")
set_buffer_keywords_ts :: proc(tokens: ^[dynamic]Token) {
    active_buffer_cstring := strings.clone_to_cstring(string(active_buffer.content))
    defer delete(active_buffer_cstring)

    tree := ts._parser_parse_string(
        active_language_server.ts_parser,
        active_buffer.previous_tree,
        active_buffer_cstring,
        u32(len(active_buffer_cstring))
    )
    
    if active_buffer.previous_tree == nil {
        error_offset := new(u32)
        error_type := new(ts.Query_Error)
        
        query := ts._query_new(ts_js_bindings.tree_sitter_javascript(), query_src, u32(len(query_src)), error_offset, error_type)
        
        if query == nil {
            fmt.println(string(query_src)[int(error_offset^):int(error_offset^+10)])
            fmt.println(error_type)
            
            return
        }
        
        active_buffer.query = query
    }
    
    cursor := ts.query_cursor_new()
    ts.query_cursor_exec(cursor, active_buffer.query, ts.tree_root_node(tree))
    
    start_point := ts.Point{
        row=u32(max(active_buffer.first_drawn_line, 0)),
        col=0,
    }
    
    end_point := ts.Point{
        row=u32(max(active_buffer.last_drawn_line, 0)),
        col=0,
    }
    
    ts.query_cursor_set_point_range(cursor, start_point, end_point)
    
    match : ts.Query_Match
    capture_count := new(u32)
    
    for ts._query_cursor_next_capture(cursor, &match, capture_count) && true {
        capture := match.captures[capture_count^]
        
        node := capture.node
        node_type := string(ts.node_type(node))

        start_point := ts.node_start_point(node)
        end_point := ts.node_end_point(node)
        
        start_byte := ts.node_start_byte(node)
        end_byte := ts.node_end_byte(node)

        override_node_type(&node_type, node, active_buffer.content, &start_point, &end_point)
        
        color := &active_language_server.ts_colors[node_type]
        
        if color == nil {
            continue
        }
        
        byte_offsets_for_range :: proc(line: string, start_rune: int, end_rune: int) -> (int, int) {
            i := 0
            rune_index := 0
            start_byte := -1
            end_byte := -1
        
            for i < len(line) {
                if rune_index == start_rune {
                    start_byte = i
                }
                if rune_index == end_rune {
                    end_byte = i
                    break
                }
                _, size := utf8.decode_rune(line[i:])
                i += size
                rune_index += 1
            }
        
            if end_byte == -1 {
                end_byte = len(line)
            }
        
            return start_byte, end_byte
        }
        
        for row in start_point.row ..= end_point.row {
            if int(row) >= len(active_buffer.lines) {
                continue
            }
        
            line := active_buffer.lines[row]
            
            start_rune := row == start_point.row ? int(start_point.col) : 0
            end_rune := row == end_point.row ? int(end_point.col) : len(line.characters)
        
            length := end_rune - start_rune
            if length <= 0 {
                continue
            }
        
            append(tokens, Token{
                char = i32(start_rune),
                line = i32(row),
                length = i32(length),
                color = color^,
                priority = 0,
            })
        }
    }
        
    active_buffer.previous_tree = tree
    
    /*
    if active_buffer.previous_tree == nil || true {
        walk_tree(ts.tree_root_node(tree), active_buffer.content, tokens, active_buffer)
        
        active_buffer.previous_tree = tree
        return
    }
    */
    
    /*
        changes_count := new(u32)
        defer free(changes_count)
        changes := ts._tree_get_changed_ranges(active_buffer.previous_tree, tree, changes_count)
        
        fmt.println(changes)
        fmt.println(string(active_buffer.content))
        active_buffer.previous_tree = tree
    
        if changes_count^ == 0 {
            tokens^ = active_buffer.tokens
            
            return
        }
            
        changed_tokens := make([dynamic]Token)
        
        change := changes[0]
        root := ts.tree_root_node(tree)
        
        walk_changed_range(root, change.start_byte, change.end_byte, active_buffer.content, &changed_tokens, active_buffer)
        
        sort_proc :: proc(token_a: Token, token_b: Token) -> int {
            if token_a.line != token_b.line {
                return int(token_a.line - token_b.line)
            } else if token_a.char != token_b.char {    
                return int(token_a.char - token_b.char)
            }
            
            return int(int(token_b.priority) - int(token_a.priority))
        }
        
        sort.quick_sort_proc(changed_tokens[:], sort_proc)
    
        if len(changed_tokens) == 0 {
            tokens^ = active_buffer.tokens
            
            return
        }
        
        first := changed_tokens[0]
        last := changed_tokens[len(changed_tokens)-1]
        
        first_byte := first.start_byte
        last_byte := last.end_byte
        filtered := make([dynamic]Token)
        
        for token in active_buffer.tokens {
            if token.end_byte <= first_byte || token.start_byte >= last_byte {
                append(&filtered, token)
            }
        }
        
        append_elems(&filtered, ..changed_tokens[:])
        sort.quick_sort_proc(filtered[:], sort_proc)
        tokens^ = filtered
    */
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
        node_type^ = strings.concatenate({type_name, "_type"}, context.temp_allocator)
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
