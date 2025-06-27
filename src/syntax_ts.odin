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

import "core:time"

import ts "../../odin-tree-sitter"

import ts_js_bindings "../../odin-tree-sitter/parsers/javascript"
import ts_ts_bindings "../../odin-tree-sitter/parsers/typescript"

import "core:sync"
tree_mutex : sync.Mutex

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
init_syntax_typescript :: proc(ext: string, allocator := context.allocator) -> os2.Error {
    parser := ts.parser_new()
    
    if ext == ".js" {
        if !ts.parser_set_language(parser, ts_js_bindings.tree_sitter_javascript()) {
            panic("Failed to set parser language to javascript.")
        }
    } else {
        if !ts.parser_set_language(parser, ts_ts_bindings.tree_sitter_typescript()) {
            panic("Failed to set parser language to typescript.")
        }
    }
    
    stdin_r, stdin_w := os2.pipe() or_return
    stdout_r, stdout_w := os2.pipe() or_return
    
    defer os2.close(stdout_w)
    defer os2.close(stdin_r)
    
    dir := fp.dir(active_buffer.file_name)
    defer delete(dir)

    desc := os2.Process_Desc{
        command = []string{"typescript-language-server", "--stdio", "--log-level", "1"},
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

    server := new(LanguageServer)
    server^ = LanguageServer{
        lsp_stdin_w = stdin_w,
        lsp_stdout_r = stdout_r,
        lsp_server_pid = process.pid,
        override_node_type=override_node_type,

        parse_tree=parse_tree,
        set_tokens=set_tokens,
        set_lsp_tokens=set_lsp_tokens,

        ts_parser=parser,
        token_types={},
        token_modifiers={},
        completion_trigger_runes={},
    }

    active_language_server = server
    language_servers[ext] = server

    msg := initialize_message(process.pid, cwd)
    defer delete(msg)

    id := "1"

    send_lsp_message(msg, id, set_capabilities, rawptr(server))

    base := fp.base(dir)

    msg_2 := did_change_workspace_folders_message(
        strings.concatenate({"file://",dir}, context.temp_allocator), dir,
    )
 
    send_lsp_init_message(msg_2, stdin_w)

    defer delete(msg_2)

    set_capabilities :: proc(response: json.Object, data: rawptr) {
        result_obj, _ := response["result"].(json.Object)

        capabilities_obj, capabilities_ok := result_obj["capabilities"].(json.Object)

        when ODIN_DEBUG {
            fmt.println("SETTING CAPABILITIES")
            fmt.println(capabilities_obj)
        }
 
        trigger_characters := (
            capabilities_obj["completionProvider"].(json.Object)
            ["triggerCharacters"].(json.Array)
        )

        trigger_runes : [dynamic]rune = {}
        for trigger_character in trigger_characters {
            r := utf8.rune_at_pos(trigger_character.(string), 0)

            append(&trigger_runes, r)
        }
       
        provider_obj, provider_ok := capabilities_obj["semanticTokensProvider"].(json.Object)
        
        legend_obj := provider_obj["legend"].(json.Object)
            
        modifiers_arr, modifiers_ok := legend_obj["tokenModifiers"].(json.Array)
        types_arr := legend_obj["tokenTypes"].(json.Array)

        server := cast(^LanguageServer)data
        
        modifiers := value_to_str_array(modifiers_arr)
        types := value_to_str_array(types_arr)

        server^.token_modifiers = modifiers
        server^.token_types = types
        server^.colors=ts_lsp_colors
        server^.ts_colors=ts_ts_colors
        server^.completion_trigger_runes=trigger_runes[:]
        
        when ODIN_DEBUG{
            fmt.println("TypeScript LSP has been initialized.")
        }

        active_buffer.previous_tree = parse_tree(0, len(active_buffer.lines))
        do_refresh_buffer_tokens = true
    }

    return os2.ERROR_NONE
}

parse_tree :: proc(first_line, last_line: int) -> ts.Tree { 
    if active_language_server == nil {
        return nil
    }

    sync.lock(&tree_mutex)

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
        
        query : ts.Query   

        if active_buffer.ext == ".js" {
            query = ts._query_new(ts_js_bindings.tree_sitter_javascript(), query_src, u32(len(query_src)), &error_offset, &error_type)
        } else {
            query = ts._query_new(ts_ts_bindings.tree_sitter_typescript(), query_src, u32(len(query_src)), &error_offset, &error_type)
        }

        if query == nil {
            fmt.println(string(query_src)[error_offset:])
            fmt.println(error_type)
            
            return nil
        }
        
        active_buffer.query = query
    }

    sync.unlock(&tree_mutex)

    set_tokens(first_line, last_line, &tree)

    return tree
}

set_tokens :: proc(first_line, last_line: int, tree_ptr: ^ts.Tree) { 
    if tree_ptr == nil {
        fmt.println("hi")
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

    /*
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

        row := int(start_point.row)
        
        line := &active_buffer.lines[row]
         
        priority : u8 = 0

        active_language_server.override_node_type(
            &node_type, node,
            active_buffer.content[:],
            &start_point, &end_point,
            &line.tokens, &priority,
        )
        
        if node_type == "SKIP" {
            continue
        }

        color := &active_language_server.ts_colors[node_type]
        
        if color == nil {
            //fmt.println(node_type, string(active_buffer.content[start_byte:end_byte]))
            continue
        }

        if row > line_number {
            line_number = row

            clear(&line.tokens)
        }
    
        start_rune := row == int(start_point.row) ? int(start_point.col) : 0
        end_rune := row == int(end_point.row) ? int(end_point.col) : len(line.characters)
    
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
    */
for ts._query_cursor_next_capture(cursor, &match, capture_index) {
    capture := match.captures[capture_index^]

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
            clear(&line.tokens)
        }

        start_rune := row == start_row ? int(start_point.col) : 0
        end_rune := row == end_row ? int(end_point.col) : len(line.characters)

        length := end_rune - start_rune
        if length <= 0 {
            continue
        }

        current_node_type := node_type
        current_priority: u8 

        active_language_server.override_node_type(
            &current_node_type, node,
            active_buffer.content[:],
            &start_point, &end_point,
            &line.tokens, &current_priority,
        )

        if current_node_type == "SKIP" {
            continue
        }

        color := &active_language_server.ts_colors[current_node_type]
        if color == nil {
            continue
        }

        append(&line.tokens, Token{
            char = i32(start_rune),
            length = i32(length),
            color = color^,
            priority = current_priority,
        })
    }
}


}

override_node_type :: proc(
    node_type: ^string,
    node: ts.Node, 
    source: []u8,
    start_point,
    end_point: ^ts.Point,
    tokens: ^[dynamic]Token,
    priority: ^u8,
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

set_lsp_tokens :: proc(buffer: ^Buffer, lsp_tokens: []Token) {
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
