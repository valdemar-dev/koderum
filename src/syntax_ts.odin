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
    "string.fragment"=GREEN,
    "string"=GREEN,

    "async"=PINK,

    "variable.declaration"=LIGHT_RED,

    "error"=RED,

    "keyword"=RED,
    "keyword.special"=PINK,

    "control.flow"=PINK,
    "constant"=ORANGE,
    "variable.builtin"=ORANGE,

    "escape_sequence"=CYAN,

    "private_field"=LIGHT_ORANGE,

    "punctuation.delimiter"=GRAY,
    "punctuation.bracket"=GRAY,
    "punctuation.parenthesis"=GRAY,
    "punctuation.special"=GRAY,

    "operator"=GRAY,

    "function.method"=YELLOW,
    "function"=YELLOW,

    "comment"=GRAY,
    "property"=LIGHT_ORANGE,
    "parameter"=LIGHT_ORANGE,

    "number"=LIGHT_GREEN,
 
    "constant.builtin"=BLUE,

    "type.builtin"=CYAN,
    "type"=PURPLE,
    "string.special"=RED,
}

query_src := strings.clone_to_cstring(strings.concatenate({`
(ERROR) @error

["meta"] @property
(property_identifier) @property

(function_expression
  name: (identifier) @function)
(function_declaration
  name: (identifier) @function)
(method_definition
  name: (property_identifier) @function.method)

(pair
  key: (property_identifier) @function.method
  value: [(function_expression) (arrow_function)])

(assignment_expression
  left: (member_expression
    property: (property_identifier) @function.method)
  right: [(function_expression) (arrow_function)])

(variable_declarator
  name: (identifier) @function
  value: [(function_expression) (arrow_function)])

(assignment_expression
  left: (identifier) @function
  right: [(function_expression) (arrow_function)])

(call_expression
  function: (identifier) @function)

(call_expression
  function: (member_expression
    property: (property_identifier) @function.method))

([
    (identifier)
    (shorthand_property_identifier)
    (shorthand_property_identifier_pattern)
 ] @constant
 (#match? @constant "^[A-Z_][A-Z\\d_]+$"))

(escape_sequence) @escape_sequence
(this) @variable.builtin
(super) @variable.builtin

[
  (true)
  (false)
  (null)
  (undefined)
] @constant.builtin

(comment) @comment

(template_string
 (string_fragment) @string)

(template_literal_type
 (string_fragment) @string)


(private_property_identifier) @private_field

(formal_parameters (required_parameter (identifier) @parameter))

(string) @string

(regex) @string.special
(number) @number

[
  ";"
  (optional_chain)
  "."
  ","
] @punctuation.delimiter

[
  "-"
  "--"
  "-="
  "+"
  "++"
  "+="
  "*"
  "*="
  "**"
  "**="
  "/"
  "/="
  "%"
  "%="
  "<"
  "<="
  "<<"
  "<<="
  "="
  "=="
  "==="
  "!"
  "!="
  "!=="
  "=>"
  ">"
  ">="
  ">>"
  ">>="
  ">>>"
  ">>>="
  "~"
  "^"
  "&"
  "|"
  "^="
  "&="
  "|="
  "&&"
  "-?:"
  "?"
  "||"
  "??"
  "&&="
  "||="
  "??="
  ":"
  "@"
  "..."
] @operator

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
  "${"
]  @punctuation.bracket

[
  "as"
  "class"
  "const"
  "continue"
  "debugger"
  "delete"
  "export"
  "extends"
  "from"
  "function"
  "get"
  "import"
  "in"
  "instanceof"
  "new"
  "return"
  "set"
  "static"
  "target"
  "typeof"
  "void"
  "yield"
] @keyword

[
  "var"
  "let"
] @variable.declaration

[
  "while"
  "if"
  "else"
  "break"
  "throw"
  "with"
  "catch"
  "finally"
  "case"
  "switch"
  "try"
  "do"
  "default"
  "of"
  "for"
] @control.flow

[
  "async"
  "await"
] @async

[
    "global"
    "module"
    "infer"
    "extends"
    "keyof"
    "as"
    "asserts"
    "is"
] @keyword.special

(type_identifier) @type
(predefined_type) @type.builtin

((identifier) @type
 (#match? @type "^[A-Z]"))

(type_arguments
  "<" @punctuation.bracket
  ">" @punctuation.bracket)

(required_parameter (identifier) @variable.parameter)
(optional_parameter (identifier) @variable.parameter)

[ "abstract"
  "declare"
  "enum"
  "export"
  "implements"
  "interface"
  "keyof"
  "namespace"
  "private"
  "protected"
  "public"
  "type"
  "readonly"
  "override"
  "satisfies"
] @keyword

`, " [\"`\"] @string"}));

ts_lsp_colors := map[string]vec4{
    "parameter"=LIGHT_ORANGE,
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
set_buffer_keywords_ts :: proc() {
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
        
        query : ts.Query   

        if active_buffer.ext == ".js" {
            query = ts._query_new(ts_js_bindings.tree_sitter_javascript(), query_src, u32(len(query_src)), error_offset, error_type)
        } else {
            query = ts._query_new(ts_ts_bindings.tree_sitter_typescript(), query_src, u32(len(query_src)), error_offset, error_type)
        }

        if query == nil {
            fmt.println(string(query_src)[int(error_offset^):int(error_offset^+1)])
            fmt.println(error_type^)
            
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
    capture_index := new(u32)
   
    line_number : u32 = 0 

    for ts._query_cursor_next_capture(cursor, &match, capture_index) {
        capture := match.captures[capture_index^]

        name_len : u32
        name := ts._query_capture_name_for_id(active_buffer.query, capture.index, &name_len)
 
        node := capture.node
        node_type := string(name)

        start_point := ts.node_start_point(node)
        end_point := ts.node_end_point(node)
        start_byte := ts.node_start_byte(node)
        end_byte := ts.node_end_byte(node)

        row := start_point.row 
        
        when ODIN_DEBUG {
            assert(row >= line_number)
            assert(start_point.row == end_point.row)
        }

        line := &active_buffer.lines[row]
         
        override_node_type(&node_type, node, active_buffer.content, &start_point, &end_point, &line.tokens)
        
        if node_type == "SKIP" {
            continue
        }

        color := &active_language_server.ts_colors[node_type]
        
        if color == nil {
            fmt.println(node_type, string(active_buffer.content[start_byte:end_byte]))
            continue
        }

        if row > line_number {
            line_number = row

            clear(&line.tokens)
        }
    
        start_rune := row == start_point.row ? int(start_point.col) : 0
        end_rune := row == end_point.row ? int(end_point.col) : len(line.characters)
    
        length := end_rune - start_rune
        if length <= 0 {
            continue
        }
    
        append(&line.tokens, Token{
            char = i32(start_rune),
            length = i32(length),
            color = color^,
            priority = 0,
        })
    }
        
    active_buffer.previous_tree = tree
}


@(private="package")
override_node_type_ts :: proc(
    node_type: ^string,
    node: ts.Node, 
    source: []u8,
    start_point,
    end_point: ^ts.Point,
    tokens: ^[dynamic]Token,
) {
    if node_type^ == "function.method" || node_type^ == "parameter" {
        resize(tokens, len(tokens)-1)
    } else if len(tokens) > 0 {
        latest_token := tokens[len(tokens)-1]

        if latest_token.char == i32(start_point.col) {
            node_type^ = "SKIP"
        }
    }
}

@(private="package")
set_buffer_tokens_threaded_ts :: proc(buffer: ^Buffer, lsp_tokens: []Token) {
    get_overlapping_token :: proc(tokens: [dynamic]Token, char: i32) -> (t: ^Token, idx: int) {
        for &token, index in tokens {
            if token.char == char {
                return &token, index
            }
        }

        return nil, -1
    }

    for token in lsp_tokens {
        if int(token.line) >= len(buffer.lines) do continue

        line := &buffer.lines[token.line]

        overlapping_token, index := get_overlapping_token(line.tokens, token.char)

        if overlapping_token == nil {
            continue
        }

        line.tokens[index] = token
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
