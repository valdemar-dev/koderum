#+feature dynamic-literals
package main

import "core:strings"
import ts "../../odin-tree-sitter"

ts_odin_colors : map[string]vec4 = {
    "string.fragment"=GREEN,
    "string"=GREEN,
    "operator"=GRAY,
    "keyword"=RED,
    "punctuation.bracket"=GRAY,
    "punctuation.delimiter"=GRAY,
    "comment"=GRAY,
    "boolean"=BLUE,
    "punctuation.special"=RED,   
    "control.flow"=PINK,
    "number"=LIGHT_GREEN,
    "float"=LIGHT_GREEN,
    "string.escape"=YELLOW,
    "function"=YELLOW,
    "variable.usage"=PINK,    
    
    "field"=LIGHT_ORANGE,    
    
    "package.name"=ORANGE,
    "build.tag"=CYAN,
    
    //"variable.builtin"=PINK,
    
    "variable"=ORANGE,
}

odin_lsp_colors := map[string]vec4{
    "function"=YELLOW,
    "variable"=ORANGE,
    "type"=CYAN,
    "namespace"=DARK_GREEN,
    "enum"=RED,
    "enumMember"=LIGHT_RED,
    "struct"=PINK,
    "parameter"=ORANGE,
    "property"=LIGHT_ORANGE,
}

ts_odin_query_src := strings.clone_to_cstring(strings.concatenate({`
;(identifier) @identifier

(call_expression
  function: (identifier) @function)

(identifier) @variable
(#eq? @variable "context")

(unary_expression
  (identifier) @variable)

(build_tag) @build.tag

(member_expression
  (_)
  (identifier) @field)

(call_expression
  function: (identifier) @function
  (#prec 2))

(package_declaration
  (identifier) @package.name)

(attribute
  (identifier) @keyword)

[
  "import"
  "package"
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
  "distinct"
  "dynamic"
  "return"
  "or_return"
  "proc"
] @keyword

[
  "if"
  "else"
  "when"
  "switch"
  "case"
  "where"
  "break"
  "for"
  "do"
  "continue"

  "or_else"
  "in"
  "not_in"

  (fallthrough_statement)
] @control.flow

((ternary_expression
  [
    "?"
    ":"
    "if"
    "else"
    "when"
  ] @conditional.ternary)
  (#set! "priority" 105))

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

[
  (comment)
  (block_comment)
] @comment
`, ""}));

odin_override_node_type :: proc(
    node_type: ^string,
    node: ts.Node, 
    source: []u8,
    start_point,
    end_point: ^ts.Point,
    tokens: ^[dynamic]Token,
    priority: ^u8,
) {
    if node_type^ == "field" {
        priority^ = priority^ +1
    }
}

