#+feature dynamic-literals
package main

WordType :: enum {
    GENERIC,
    NUMBER,
    KEYWORD,
    FUNCTION,
    DECLARATION,
    SPECIAL,
    TYPE,
}

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
}

js_keyword_map : map[string]WordType = {
    "for"=.KEYWORD,

    "continue"=.KEYWORD,
    "return"=.KEYWORD,
    "with"=.KEYWORD,

    "function"=.FUNCTION,

    "const"=.DECLARATION,
    "let"=.DECLARATION,
    "var"=.DECLARATION,
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
