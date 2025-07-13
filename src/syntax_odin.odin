#+feature dynamic-literals
package main

import "core:strings"
import ts "../../odin-tree-sitter"

ts_odin_colors : map[string]vec4 = {
    "string.fragment"=TOKEN_COLOR_02,
    "string"=TOKEN_COLOR_02,
    "operator"=TOKEN_COLOR_03,
    "keyword"=TOKEN_COLOR_00,
    "punctuation.bracket"=TOKEN_COLOR_03,
    "punctuation.delimiter"=TOKEN_COLOR_03,
    "comment"=TOKEN_COLOR_03,
    "boolean"=TOKEN_COLOR_09,
    "punctuation.special"=TOKEN_COLOR_00,
    "control.flow"=TOKEN_COLOR_10,
    "number"=TOKEN_COLOR_11,
    "float"=TOKEN_COLOR_11,
    "string.escape"=TOKEN_COLOR_04,
    "function"=TOKEN_COLOR_04,
    "variable.usage"=TOKEN_COLOR_10,
    "field"=TOKEN_COLOR_06,
    "package.name"=TOKEN_COLOR_05,
    "build.tag"=TOKEN_COLOR_07,
    "variable"=TOKEN_COLOR_05,
}

odin_lsp_colors := map[string]vec4{
    "function"=TOKEN_COLOR_04,
    "variable"=TOKEN_COLOR_05,
    "type"=TOKEN_COLOR_07,
    "namespace"=TOKEN_COLOR_14,
    "enum"=TOKEN_COLOR_00,
    "enumMember"=TOKEN_COLOR_01,
    "struct"=TOKEN_COLOR_10,
    "parameter"=TOKEN_COLOR_05,
    "property"=TOKEN_COLOR_06,
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
  )

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

