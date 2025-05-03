#+feature dynamic-literals
package main

c_keywords_map : map[string]WordType = {
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

    "const"=WordType{
        match_proc=whole_word_match,
        color=RED,
    },

    "if"=WordType{
        match_proc=whole_word_match,
        color=RED,
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

    "//" = WordType {
        match_proc=line_starts_match,
        color=GRAY,
    },


    "enum" = WordType {
        match_proc=whole_word_match,
        color=ORANGE,
    },

    "struct" = WordType {
        match_proc=whole_word_match,
        color=ORANGE,
    },

    "typedef" = WordType {
        match_proc=whole_word_match,
        color=ORANGE,
    },

    "#include" = WordType {
        match_proc=whole_word_match,
        color=CYAN,
    },

    "#define" = WordType {
        match_proc=whole_word_match,
        color=CYAN,
    },

    "#ifdef" = WordType {
        match_proc=whole_word_match,
        color=CYAN,
    },

    "#endif" = WordType {
        match_proc=whole_word_match,
        color=CYAN,
    },

    //TYPEDEFS

    "int" = WordType {
        match_proc=whole_word_match,
        color=RED,
    },

    "float" = WordType {
        match_proc=whole_word_match,
        color=RED,
    },

    "char" = WordType {
        match_proc=whole_word_match,
        color=RED,
    },

    "void" = WordType {
        match_proc=whole_word_match,
        color=RED,
    },
}

c_string_chars : map[rune]vec4 = {
    '"'=GREEN,
    '\''=RED,
}
