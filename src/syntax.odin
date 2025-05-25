#+feature dynamic-literals
package main

import "core:unicode/utf8"

WordType :: struct {
    match_proc: proc (comp: string, value: string, buffer_line: ^BufferLine) -> bool,
    color: vec4,
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

match_all :: proc(comp: string, target: string, buffer_line: ^BufferLine) -> bool {
    return true
}

whole_word_match :: proc(comp: string, target: string, buffer_line: ^BufferLine) -> bool {
    return comp == target
}

line_starts_match :: proc(comp: string, target: string, buffer_line: ^BufferLine) -> bool {
    if len(buffer_line.characters) < len(comp) {
        return false
    }

    string_val := utf8.runes_to_string(buffer_line.characters[0:len(comp)])
    defer delete(string_val)

    if string_val == comp {
        return true
    }

    return false
}

word_break_chars : []rune = {
    ' ',
}