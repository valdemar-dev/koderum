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

ts_odin_query_src := strings.clone_to_cstring(strings.concatenate({``, ""}));

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

