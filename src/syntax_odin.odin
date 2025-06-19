
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

import ts_odin_bindings "../../odin-tree-sitter/parsers/odin"

ts_odin_colors : map[string]vec4 = {
    "string.fragment"=GREEN,
    "string"=GREEN,
}

query_src := strings.clone_to_cstring(strings.concatenate({`
; Preprocs

[
  (calling_convention)
  (tag)
] @preproc

; Includes

[
  "import"
  "package"
] @include

; Keywords

[
  "foreign"
  "using"
  "struct"
  "enum"
  "union"
  "defer"
  "cast"
  "transmute"
  "auto_cast"
  "map"
  "bit_set"
  "matrix"
  "bit_field"
] @keyword

[
  "proc"
] @keyword.function

[
  "return"
  "or_return"
] @keyword.return

[
  "distinct"
  "dynamic"
] @storageclass

; Conditionals

[
  "if"
  "else"
  "when"
  "switch"
  "case"
  "where"
  "break"
  (fallthrough_statement)
] @conditional

((ternary_expression
  [
    "?"
    ":"
    "if"
    "else"
    "when"
  ] @conditional.ternary)
  (#set! "priority" 105))

; Repeats

[
  "for"
  "do"
  "continue"
] @repeat

; Variables

(identifier) @variable

; Namespaces

(package_declaration (identifier) @namespace)

(import_declaration alias: (identifier) @namespace)

(foreign_block (identifier) @namespace)

(using_statement (identifier) @namespace)

; Parameters

(parameter (identifier) @parameter ":" "="? (identifier)? @constant)

(default_parameter (identifier) @parameter ":=")

(named_type (identifier) @parameter)

(call_expression argument: (identifier) @parameter "=")

; Functions

(procedure_declaration (identifier) @type)

(procedure_declaration (identifier) @function (procedure (block)))

(procedure_declaration (identifier) @function (procedure (uninitialized)))

(overloaded_procedure_declaration (identifier) @function)

(call_expression function: (identifier) @function.call)

; Types

(type (identifier) @type)

((type (identifier) @type.builtin)
  (#any-of? @type.builtin
    "bool" "byte" "b8" "b16" "b32" "b64"
    "int" "i8" "i16" "i32" "i64" "i128"
    "uint" "u8" "u16" "u32" "u64" "u128" "uintptr"
    "i16le" "i32le" "i64le" "i128le" "u16le" "u32le" "u64le" "u128le"
    "i16be" "i32be" "i64be" "i128be" "u16be" "u32be" "u64be" "u128be"
    "float" "double" "f16" "f32" "f64" "f16le" "f32le" "f64le" "f16be" "f32be" "f64be"
    "complex32" "complex64" "complex128" "complex_float" "complex_double"
    "quaternion64" "quaternion128" "quaternion256"
    "rune" "string" "cstring" "rawptr" "typeid" "any"))

"..." @type.builtin

(struct_declaration (identifier) @type "::")

(enum_declaration (identifier) @type "::")

(union_declaration (identifier) @type "::")

(bit_field_declaration (identifier) @type "::")

(const_declaration (identifier) @type "::" [(array_type) (distinct_type) (bit_set_type) (pointer_type)])

(struct . (identifier) @type)

(field_type . (identifier) @namespace "." (identifier) @type)

(bit_set_type (identifier) @type ";")

(procedure_type (parameters (parameter (identifier) @type)))

(polymorphic_parameters (identifier) @type)

((identifier) @type
  (#lua-match? @type "^[A-Z][a-zA-Z0-9]*$")
  (#not-has-parent? @type parameter procedure_declaration call_expression))

; Fields

(member_expression "." (identifier) @field)

(struct_type "{" (identifier) @field)

(struct_field (identifier) @field "="?)

(field (identifier) @field)

; Constants

((identifier) @constant
  (#lua-match? @constant "^_*[A-Z][A-Z0-9_]*$")
  (#not-has-parent? @constant type parameter))

(member_expression . "." (identifier) @constant)

(enum_declaration "{" (identifier) @constant)

; Macros

((call_expression function: (identifier) @function.macro)
  (#lua-match? @function.macro "^_*[A-Z][A-Z0-9_]*$"))

; Attributes

(attribute (identifier) @attribute "="?)

; Labels

(label_statement (identifier) @label ":")

; Literals

(number) @number

(float) @float

(string) @string

(character) @character

(escape_sequence) @string.escape

(boolean) @boolean

[
  (uninitialized)
  (nil)
] @constant.builtin

((identifier) @variable.builtin
  (#any-of? @variable.builtin "context" "self"))

; Operators

[
  ":="
  "="
  "+"
  "-"
  "*"
  "/"
  "%"
  "%%"
  ">"
  ">="
  "<"
  "<="
  "=="
  "!="
  "~="
  "|"
  "~"
  "&"
  "&~"
  "<<"
  ">>"
  "||"
  "&&"
  "!"
  "^"
  ".."
  "+="
  "-="
  "*="
  "/="
  "%="
  "&="
  "|="
  "^="
  "<<="
  ">>="
  "||="
  "&&="
  "&~="
  "..="
  "..<"
  "?"
] @operator

[
  "or_else"
  "in"
  "not_in"
] @keyword.operator

; Punctuation

[ "{" "}" ] @punctuation.bracket

[ "(" ")" ] @punctuation.bracket

[ "[" "]" ] @punctuation.bracket

[
  "::"
  "->"
  "."
  ","
  ":"
  ";"
] @punctuation.delimiter


[
  "@"
  "$"
] @punctuation.special

; Comments

[
  (comment)
  (block_comment)
] @comment @spell

; Errors

(ERROR) @error
`, ""}));

odin_lsp_colors := map[string]vec4{
    "parameter"=LIGHT_ORANGE,
}

@(private="package")
init_syntax_odin :: proc(ext: string, allocator := context.allocator) -> (server: ^LanguageServer, err: os2.Error) {
    parser := ts.parser_new()
    
    if !ts.parser_set_language(parser, ts_odin_bindings.tree_sitter_odin()) {
        fmt.println("Failed to set parser language")
        return
    }
    
    stdin_r, stdin_w := os2.pipe() or_return
    stdout_r, stdout_w := os2.pipe() or_return
    
    defer os2.close(stdout_w)
    defer os2.close(stdin_r)
    
    dir := fp.dir(active_buffer.file_name)
    defer delete(dir)

    desc := os2.Process_Desc{
        command = []string{"ols"},
        env = nil,
        working_dir = "/usr/bin/ols",
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

    defer delete(bytes)

    if read_err != os2.ERROR_NONE {
        return server,read_err
    }
    
    when ODIN_DEBUG {
        fmt.println("LSP RESPONSE", string(bytes))
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
        colors=odin_lsp_colors,
        ts_colors=ts_odin_colors,
    }
 
    when ODIN_DEBUG{
        fmt.println("TypeScript LSP has been initialized.")
    }
    
    return server,os2.ERROR_NONE
}

@(private="package")
set_buffer_keywords_odin :: proc() {
    active_buffer_cstring := strings.clone_to_cstring(string(active_buffer.content[:]))
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
        
        query := ts._query_new(ts_odin_bindings.tree_sitter_odin(), query_src, u32(len(query_src)), error_offset, error_type)

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
   
    line_number : int = -1

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
        
        when ODIN_DEBUG {
            assert(row >= line_number)
            assert(start_point.row == end_point.row)
        }

        line := &active_buffer.lines[row]
         
        override_node_type(&node_type, node, active_buffer.content[:], &start_point, &end_point, &line.tokens)
        
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
        
    active_buffer.previous_tree = tree
}


@(private="package")
override_node_type_odin :: proc(
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
set_buffer_tokens_threaded_odin :: proc(buffer: ^Buffer, lsp_tokens: []Token) {
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
