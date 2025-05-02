#+feature dynamic-literals
package main

WordType :: struct {
    match_proc: proc (comp: string, value: string) -> bool,
    color: vec4,
}

//WordType :: enum {
//    GENERIC,
//    NUMBER,
//   WordType{,
//    FUNCTION,
//    DECLARATION,
//    SPECIAL,
//    TYPE,
//    BOOL,
//}

indent_rule_language_list : map[string]^map[rune]IndentRule = {
    ".txt"=&generic_indent_rule_list,
    ".odin"=&generic_indent_rule_list,
    ".glsl"=&generic_indent_rule_list,
    ".c"=&generic_indent_rule_list,
    ".cpp"=&generic_indent_rule_list,

    ".js"=&generic_indent_rule_list,
    ".ts"=&generic_indent_rule_list,

    ".python"=&python_indent_rule_list,
}

generic_indent_rule_list : map[rune]IndentRule = {
    '{'=IndentRule{
        type=.FORWARD,
    },

    '('=IndentRule{
        type=.FORWARD,
    },

    '['=IndentRule{
        type=.FORWARD,
    },
}

python_indent_rule_list : map[rune]IndentRule = {
    ':'=IndentRule{
        type=.FORWARD,
    },

    '('=IndentRule{
        type=.FORWARD,
    },

    '{'=IndentRule{
        type=.FORWARD,
    },

    '['=IndentRule{
        type=.FORWARD,
    },
}

match_all :: proc(comp: string, target: string) -> bool {
    return true
}

whole_word_match :: proc(comp: string, target: string) -> bool {
    return comp == target
}

js_keyword_map : map[string]WordType = {
    "for"=WordType{
        match_proc=whole_word_match,
        color=ORANGE,
    },

    "continue"=WordType{
        match_proc=whole_word_match,
        color=ORANGE,
    },

    "return"=WordType{
        match_proc=whole_word_match,
        color=ORANGE,
    },

    "with"=WordType{
        match_proc=whole_word_match,
        color=ORANGE,
    },

    "function"=WordType{
        match_proc=whole_word_match,
        color=CYAN,
    },

    "const"=WordType{
        match_proc=whole_word_match,
        color=RED,
    },

    "let"=WordType{
        match_proc=whole_word_match,
        color=RED,
    },

    "var"=WordType{
        match_proc=whole_word_match,
        color=RED,
    },

    "if"=WordType{
        match_proc=whole_word_match,
        color=RED,
    },

    "try"=WordType{
        match_proc=whole_word_match,
        color=RED,
    },

    "catch"=WordType{
        match_proc=whole_word_match,
        color=RED,
    },

    "finally"=WordType{
        match_proc=whole_word_match,
        color=RED,
    },

    "this"=WordType{
        match_proc=whole_word_match,
        color=ORANGE,
    },

    "switch"=WordType{
        match_proc=whole_word_match,
        color=RED,
    },

    "case"=WordType{
        match_proc=whole_word_match,
        color=RED,
    },

    "default"=WordType{
        match_proc=whole_word_match,
        color=RED,
    },

    "break"=WordType{
        match_proc=whole_word_match,
        color=ORANGE,
    },

    "throw" = WordType{
        match_proc=whole_word_match,
        color=RED,
    },

    "new" = WordType{
        match_proc=whole_word_match,
        color=ORANGE,
    },

    "in" = WordType {
        match_proc=whole_word_match,
        color=ORANGE,
    }
}


keyword_language_list : map[string]^map[string]WordType = {
    ".js"=&js_keyword_map,
}

js_string_chars : map[rune]vec4 = {
    '"'=GREEN,
    '\''=RED,
    '`'=GREEN,
}

string_char_language_list : map[string]^map[rune]vec4 = {
    ".js"=&js_string_chars,
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
    '='=GRAY,
    '>'=GRAY,
    '<'=GRAY,
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
}
