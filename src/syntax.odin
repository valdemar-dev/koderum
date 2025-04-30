#+feature dynamic-literals
package main

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

indent_rule_language_list : map[string]^map[rune]IndentRule = {
    ".txt"=&generic_indent_rule_list,
    ".odin"=&generic_indent_rule_list,
    ".glsl"=&generic_indent_rule_list,
    ".c"=&generic_indent_rule_list,
    ".cpp"=&generic_indent_rule_list,
    ".python"=&python_indent_rule_list,
}

js_keyword_map : map[string]WordType = {
    "for"=.KEYWORD,
    "continue"=.KEYWORD,
    "const"=.KEYWORD,
    "let"=.KEYWORD,
    "return"=.KEYWORD,
    "with"=.KEYWORD,
}

keyword_language_list : map[string]^map[string]WordType = {
    ".js"=&js_keyword_map,
}

StringVariant :: enum {
    A,
    B,
    C,
}

string_variants : map[StringVariant]vec4 = {
    .A=RED,
    .B=GREEN,
}

js_string_chars : map[rune]StringVariant = {
    '"'=.A,
    '\''=.B,
    '`'=.A,
}

string_char_language_list : map[string]^map[rune]StringVariant = {
    ".js"=&js_string_chars,
}

highlight_colors : map[WordType]vec4 = {
    .KEYWORD=RED,

    .STRING=GREEN,
}

