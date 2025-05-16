#+feature dynamic-literals
package main

match_import :: proc () -> bool {
    return true
}

odin_keywords_map : map[string]WordType = {
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

    "u8" = WordType {
        match_proc=whole_word_match,
        color=PURPLE,
    },

    "u16" = WordType {
        match_proc=whole_word_match,
        color=PURPLE,
    },    

    "u32" = WordType {
        match_proc=whole_word_match,
        color=PURPLE,
    },
  
    "u64" = WordType {
        match_proc=whole_word_match,
        color=PURPLE,
    },

    "f32" = WordType {
        match_proc=whole_word_match,
        color=PURPLE,
    },

    "f16" = WordType {
        match_proc=whole_word_match,
        color=PURPLE,
    },

    "f64" = WordType {
        match_proc=whole_word_match,
        color=PURPLE,
    },
        
    "i64" = WordType {
        match_proc=whole_word_match,
        color=PURPLE,
    },

    "i32" = WordType { 
        match_proc=whole_word_match,
        color=PURPLE,
    },

    "int" = WordType {
        match_proc=whole_word_match,
        color=PURPLE,
    },

    "rune" = WordType {
        match_proc=whole_word_match,
        color=RED,
    },

    "string" = WordType {
        match_proc=whole_word_match,
        color=GREEN,
    },

    "map" = WordType {
        match_proc=whole_word_match,
        color=ORANGE,
    },

    "bool" = WordType {
        match_proc=whole_word_match,
        color=RED,
    },

    "true" = WordType {
        match_proc=whole_word_match,
        color=RED,
    },

    "false" = WordType {
        match_proc=whole_word_match,
        color=RED,
    },

    "proc" = WordType {
        match_proc=whole_word_match,
        color=CYAN,
    },
}

odin_string_chars : map[rune]vec4 = {
    '"'=GREEN,
    '\''=RED,
}
