#+feature dynamic-literals
#+private file
package main

import "core:os/os2"
import "core:fmt"
import "core:os"
import "core:strings"
import fp "core:path/filepath"
import "core:encoding/json"
import "core:text/regex"
import "core:unicode/utf8"

@(private="package")
spawn_ts_server :: proc(allocator := context.allocator) -> (server: ^LanguageServer, err: os2.Error) {
    stdin_r, stdin_w := os2.pipe() or_return
    stdout_r, stdout_w := os2.pipe() or_return
    
    defer os2.close(stdout_w)
    defer os2.close(stdin_r)
    
    dir := fp.dir(active_buffer.file_name)
    defer delete(dir)

    desc := os2.Process_Desc{
        command = []string{"typescript-language-server", "--stdio"},
        env = nil,
        working_dir = dir,
        stdin  = stdin_r,
        stdout = stdout_w,
        stderr = nil,
    }

    process, start_err := os2.process_start(desc)
    if start_err != os2.ERROR_NONE {
        panic("Failed to start TypeScript language server: ")
    }

    msg := initialize_message(process.pid, dir)
    
    when ODIN_DEBUG {
        fmt.println("LSP REQUEST", msg)
    }
    
    _, write_err := os2.write(stdin_w, transmute([]u8)msg)
    if write_err != os2.ERROR_NONE {
        return server,write_err
    }
    
    delete(msg)

    bytes, read_err := read_lsp_message(stdout_r, allocator)
    if read_err != os2.ERROR_NONE {
        return server,read_err
    }
    
    when ODIN_DEBUG {
        fmt.println("LSP RESPONSE", string(bytes))
    }
    
    delete(bytes)
    
    base := fp.base(dir)
    
    msg = did_change_workspace_folders_message(
        strings.concatenate({"file://",dir}), base
    )
    
    when ODIN_DEBUG {
        fmt.println("LSP REQUEST", msg)
    }
    
    _, write_err = os2.write(stdin_w, transmute([]u8)msg)
    if write_err != os2.ERROR_NONE {
        return server,write_err
    }
    
    bytes, read_err = read_lsp_message(stdout_r, allocator)
    defer delete(bytes)
    
    if read_err != os2.ERROR_NONE {
        return server,read_err
    }
    
    parsed,_ := json.parse(bytes)
    
    obj, obj_ok := parsed.(json.Object)
    
    if !obj_ok {
        panic("Received incorrect packet.")
    }
    
    result_obj, result_ok := obj["result"].(json.Object)
    
    if !result_ok {
        panic("Missing result from lsp packet.")
    }
    
    capabilities_obj, capabilities_ok := result_obj["capabilities"].(json.Object)
    
    if !capabilities_ok {
        panic("Missing result from lsp packet.")
    }
    
    provider_obj, provider_ok := capabilities_obj["semanticTokensProvider"].(json.Object)
    
    if !provider_ok {
        panic("Missing semanticTokensProvider from lsp response.")
    }
    
    legend_obj, legend_ok := provider_obj["legend"].(json.Object)
    
    if !provider_ok {
        panic("Missing legend from lsp response.")
    }
    
    modifiers_arr, modifiers_ok := legend_obj["tokenModifiers"].(json.Array)
    types_arr, types_ok := legend_obj["tokenTypes"].(json.Array)
    
    if !modifiers_ok || !types_ok {
        panic("LSP Legend did not contain types or modifiers.")
    }
    
    modifiers := value_to_str_array(modifiers_arr)
    types := value_to_str_array(types_arr)
    
    fmt.println(types)
    fmt.println(modifiers)
    
    server = new(LanguageServer)
    server^ = LanguageServer{
        lsp_stdin_w = stdin_w,
        lsp_stdout_r = stdout_r,
        lsp_server_pid = process.pid,
        token_modifiers = modifiers,
        token_types = types,
    }
    
    when ODIN_DEBUG{
        fmt.println("TypeScript LSP has been initialized.")
    }
    
    return server,os2.ERROR_NONE
}

keywords : []string = {
    "for",
    "in",
    "of",
    "const",
    "let",
    "return",
    "function",
    "if",
    "else",
    "var",
    "with",
    "import",
    "export",
    "from",
}

check_for_keyword :: proc(
    token_string: string,
    line_index: int,
    char: i32,
    length: i32,
    line: ^BufferLine,
) -> bool {
    for keyword in keywords {
        if token_string != keyword {
            continue
        }
                
        token := Token{
            line = i32(line_index),
            char = char,
            length = length,
            type = "keyword",
        }
        fmt.println("KEYWORD")
        
        append(&line.tokens, token)
        
        return false
    }
    
    return true
}


set_token :: proc(
    token_string: string,
    line_index: int,
    char: i32,
    length: i32,
    line: ^BufferLine,
) -> bool {
    check_for_keyword(
        token_string,
        line_index,
        char,
        length,
        line,
    ) or_return
    
    return true
}

TokenTypeOverride :: enum {
    NONE,
    
    STRING,
    
    SINGE_LINE_COMMENT,
    MULTI_LINE_COMMENT,
    
    REGEXP,
}

@(private="package")
set_buffer_keywords_ts :: proc() {
    delimiters := []string{
        " ", "\t", "\n", "\r",
        "(", ")", "[", "]", "{", "}", ".", ",", ";", ":", "?", "!", "~",
        "+", "-", "*", "/", "%", "^", "&", "|", "=", "<", ">", "\"", "'", "`",
        "@", "#", "\\",
    }
    
    rune_str_buf := make([dynamic]rune)
    
    token_type_override : TokenTypeOverride = .NONE
    
    string_runes := []rune{
        '`', '\'', '"',
    }
    
    string_width := 0
    string_char : rune
    
    for &line, line_index in active_buffer.lines {
        str := utf8.runes_to_string(line.characters[:])
        start := -1
        
        str_loop: for i in 0..<len(str) {
            r := str[i]
            
            clear(&rune_str_buf)
            append(&rune_str_buf, rune(r))
            
            ch := utf8.runes_to_string(rune_str_buf[:])
            
            #partial switch token_type_override {
            case .NONE:
                for string_rune in string_runes {
                    if rune(r) == string_rune {
                        token_type_override = .STRING
                        string_char = rune(r)
                        
                        start = i
                    
                        continue str_loop
                    }
                }
                
                break
            case .STRING:
                string_width += 1
                
                if rune(r) == string_char {
                    token_type_override = .NONE
                    string_char = ' '
                    
                    token := Token{
                        line = i32(line_index),
                        char = i32(start),
                        length = i32(string_width+1),
                        type = "string"
                    }
            
                    append(&line.tokens, token)
            
                    string_width = 0

                }
                
                continue
            }
            
            is_delim := false
            for d in delimiters {
                if d == ch {
                    is_delim = true
                }
            }

            if is_delim {
                if start != -1 {
                    char := i32(start)
                    length := i32(i - start)
                    
                    end_idx := char + length
                    
                    token_string := str[char:end_idx]
                    
                    set_token(
                        token_string,
                        line_index,
                        char,
                        length,
                        &line
                    )
                    
                    start = -1
                }
                continue
            }

            if start == -1 {
                start = i
            }
        }
        
        #partial switch token_type_override {
        case .STRING:
            token := Token{
                line = i32(line_index),
                char = i32(start),
                length = i32(string_width+1),
                type = "string"
            }
            
            append(&line.tokens, token)
            
            string_width = 0
            
            fmt.println("palsdkfjpaskld")
            
            continue
        }

        if start != -1 {
            char := i32(start)
            length := i32(len(line.characters)) - i32(start)
            
            end_idx := char + length
            
            token_string := str[char:end_idx]
            
            set_token(
                token_string,
                line_index,
                char,
                length,
                &line
            )
        }
    }
}




