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

@(private="package")
keyword_language_list : map[string]^map[string]WordType = {
    ".js"=&js_keywords_map,
    ".ts"=&js_keywords_map,
    ".c"=&c_keywords_map,
    ".odin"=&odin_keywords_map,
}

@(private="package")
string_char_language_list : map[string]^map[rune]vec4 = {
    ".js"=&js_string_chars,
    ".ts"=&js_string_chars,
    ".c"=&c_string_chars,
    ".odin"=&odin_string_chars,
}

special_chars : map[rune]vec4 = {
    '('=GRAY,
    ')'=GRAY,
    '['=GRAY,
    ']'=GRAY,
    '{'=GRAY,
    '}'=GRAY,
    '-'=GRAY,
    '/'=GRAY,
    '.'=GRAY,
    ':'=GRAY,
    ';'=GRAY,
    '+'=GRAY,
    '='=GRAY,
    '>'=GRAY,
    '<'=GRAY,
    '|'=GRAY,
    '1'=CYAN,
    '2'=CYAN,
    '3'=CYAN,
    '4'=CYAN,
    '5'=CYAN,
    '6'=CYAN,
    '7'=CYAN,
    '8'=CYAN,
    '9'=CYAN,
    '0'=CYAN,
}

word_break_chars : []rune = {
    '\'',
    '.',
    ' ',
    '{',
    '}',
    '[',
    ']',
    '(',
    ')',
    '"',
    ':',
    ';',
    '/',
    '<',
    '>',
    '|',
    '=',
    ',',
    '-',
    '+',
}
