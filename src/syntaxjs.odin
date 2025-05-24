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

JSDataType :: enum {
    string=1,
    number=2,
    float=3,
    boolean=4,
    object=5,
    array=6,
}

JSToken :: struct {
    data_type: JSDataType,
}

@(private="package")
set_buffer_tokens_js :: proc(buffer: ^Buffer) {
    for line in buffer.lines {
        
    }
}

js_string_chars : map[rune]vec4 = {
    '"'=GREEN,
    '\''=RED,
    '`'=GREEN,
}
