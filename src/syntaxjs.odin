#+feature dynamic-literals
package main

js_keywords_map : map[string]WordType = {
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
    },

    "//" = WordType {
        match_proc=line_starts_match,
        color=GRAY,
    }
}

js_string_chars : map[rune]vec4 = {
    '"'=GREEN,
    '\''=RED,
    '`'=GREEN,
}
