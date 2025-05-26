#+feature dynamic-literals
package main

import "core:unicode/utf8"
import "core:os/os2"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:fmt"
import "core:io"
import "core:encoding/json"

LanguageServer :: struct {
    lsp_stdin_w : ^os2.File,
    lsp_stdout_r : ^os2.File,
    lsp_server_pid : int,
    
    token_types : []string,
    token_modifiers : []string,
}

lsp_request_id := 10

active_language_server : ^LanguageServer

language_servers : map[string]^LanguageServer = {}

set_active_language_server :: proc(ext: string) {
    active_language_server = nil
    
    switch ext {
    case ".js",".ts":
        if ext not_in language_servers {
            server,err := spawn_ts_server()
            
            if err != os2.ERROR_NONE {
                return
            }
            
            if server == nil {
                return
            }
            
            language_servers[ext] = server
            active_language_server = server
            
            return
        } else {
            active_language_server = language_servers[ext]
        }
    }
}

lsp_handle_file_open :: proc() {
    set_active_language_server(active_buffer.ext)
    
    if active_language_server == nil {
        return
    }
    
    serialized_buffer := serialize_buffer(active_buffer)
    escaped := escape_json(serialized_buffer)
    
    defer delete(serialized_buffer)
    
    msg := did_open_message(
        strings.concatenate({"file://",active_buffer.file_name}),
        "typescript",
        1,
        escaped,
    )
    
    when ODIN_DEBUG {
        fmt.println("LSP REQUEST", msg)
    }
    
    _, write_err := os2.write(active_language_server.lsp_stdin_w, transmute([]u8)msg)
}


Token :: struct {
    line:        i32,
    char:        i32,
    length:      i32,
    type:        string,
    modifiers:   []string,
}

decode_modifiers :: proc(bitset: i32, modifiers: []string) -> []string {
    result := make([dynamic]string)
    
    for i in 0..<len(modifiers) {
        if (bitset & (1 << u32(i))) != 0 {
            append(&result, modifiers[i])
        }
    }
    return result[:]
}

decode_semantic_tokens :: proc(data: []i32, token_types: []string, token_modifiers: []string) -> [dynamic]Token {
    tokens := make([dynamic]Token)
    
    line: i32 = 0
    char: i32 = 0

    for i in 0..<len(data) / 5 {
        idx := i * 5
        delta_line := data[idx + 0]
        delta_char := data[idx + 1]
        length := data[idx + 2]
        token_type_index := data[idx + 3]
        token_mod_bitset := data[idx + 4]

        line += delta_line
        
        if delta_line == 0 {
            char += delta_char
        } else {
            char = delta_char
        }

        t := Token{
            line = line,
            char = char,
            length = length,
            type = token_types[token_type_index],
            modifiers = decode_modifiers(token_mod_bitset, token_modifiers),
        }
        
        append(&tokens, t)
    }

    return tokens
}

set_buffer_tokens :: proc() {
    if active_language_server == nil {
        return
    }
    
    lsp_request_id += 1
    
    msg := semantic_tokens_request_message(
        lsp_request_id,
        strings.concatenate({"file://",active_buffer.file_name}),
        0, len(active_buffer.lines)
    )
    
    when ODIN_DEBUG {
        fmt.println("LSP REQUEST", msg)
    }

    _, write_err := os2.write(active_language_server.lsp_stdin_w, transmute([]u8)msg)
    
    bytes, read_err := read_lsp_message(active_language_server.lsp_stdout_r, context.allocator)
    
    when ODIN_DEBUG {
        fmt.println("LSP RESPONSE", string(bytes))
    }
    
    if read_err != os2.ERROR_NONE {
        return
    }
    
    parsed,_ := json.parse(bytes)
    obj, ok := parsed.(json.Object)
    
    if !ok {
        panic("Malformed json in set_buffer_tokens")
    }
    
    result := obj["result"]
    obj,ok = result.(json.Object)
    
    if !ok {
        panic("Malformed json in set_buffer_tokens")
    }
    
    data,data_ok := obj["data"].(json.Array)
    
    if !data_ok {
        panic("Malformed json in set_buffer_tokens")
    }
    
    tokens : [dynamic]i32
    
    for value in data {
        append(&tokens, i32(value.(f64)))
    }
    
    decoded_tokens := decode_semantic_tokens(
        tokens[:],
        active_language_server.token_types,
        active_language_server.token_modifiers,
    )
}

read_lsp_message :: proc(file: ^os2.File, allocator := context.allocator) -> ([]u8, os2.Error) {
    header_buf: [dynamic]u8
    header_buf.allocator = allocator

    temp: [1]u8
    delimiter := "\r\n\r\n"
    match_len := 0

    for match_len < 4 {
        n, err := os2.read(file, temp[:])
        if err != os2.ERROR_NONE || n != 1 {
            return nil, err
        }

        _, append_err := append(&header_buf, temp[0])
        if append_err != nil {
            return nil, os2.ERROR_NONE
        }

        if temp[0] == delimiter[match_len] {
            match_len += 1
        } else {
            match_len = 0
        }
    }

    header_str := string(header_buf[:])
    content_len := 0
    for line in strings.split_lines(header_str) {
        if strings.starts_with(line, "Content-Length:") {
            suffix := strings.trim(strings.trim_prefix(line, "Content-Length:"), " ")
            content_len = strconv.atoi(suffix)
            break
        }
    }

    if content_len == 0 {
        return nil, os2.ERROR_NONE // malformed
    }

    body_buf: [dynamic]u8
    body_buf.allocator = allocator
    left := content_len

    for left > 0 {
        temp_size := min(left, 1024)
        temp_read: [1024]u8
        n, err := os2.read(file, temp_read[:temp_size])
        if err != os2.ERROR_NONE {
            return nil, err
        }
        if n == 0 {
            break
        }
        _, append_err := append(&body_buf, ..temp_read[:n])
        if append_err != nil {
            return nil, os2.ERROR_NONE
        }
        left -= n
    }

    return body_buf[:], os2.ERROR_NONE
}

did_change_workspace_folders_message :: proc(folder_uri: string, folder_name: string) -> string {
    json := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"method\": \"workspace/didChangeWorkspaceFolders\",\n",
        "  \"params\": {\n",
        "    \"event\": {\n",
        "      \"added\": [\n",
        "        {\n",
        "          \"uri\": \"", folder_uri, "\",\n",
        "          \"name\": \"", folder_name, "\"\n",
        "        }\n",
        "      ],\n",
        "      \"removed\": []\n",
        "    }\n",
        "  }\n",
        "}\n",
    })

    buf := make([dynamic]u8, 32)
    length := strconv.itoa(buf[:], len(json))

    header := strings.concatenate({
        "Content-Length: ", length, "\r\n",
        "\r\n",
        json,
    })

    delete(buf)
    return header
}


initialize_message :: proc(pid: int, project_dir: string) -> string {
    buf := make([dynamic]u8, 32)
    str_pid := strconv.itoa(buf[:], pid)

    json := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"id\": \"1\",\n",
        "  \"method\": \"initialize\",\n",
        "  \"params\": {\n",
        "    \"processId\": ", str_pid, ",\n",
        "    \"rootUri\": \"file://", project_dir, "\",\n",
        "    \"capabilities\": {}\n",
        "  }\n",
        "}\n",
    })

    delete(buf)
    buf = make([dynamic]u8, 32)
    length := strconv.itoa(buf[:], len(json))

    return strings.concatenate({
        "Content-Length: ", length, "\r\n",
        "\r\n",
        json,
    })
}

did_open_message :: proc(uri: string, languageId: string, version: int, text: string) -> string {
    json := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"method\": \"textDocument/didOpen\",\n",
        "  \"params\": {\n",
        "    \"textDocument\": {\n",
        "      \"uri\": \"", uri, "\",\n",
        "      \"languageId\": \"", languageId, "\",\n",
        "      \"version\": ", strconv.itoa(make([dynamic]u8, 16)[:], version), ",\n",
        "      \"text\": \"", text, "\"\n",
        "    }\n",
        "  }\n",
        "}\n",
    })

    buf := make([dynamic]u8, 32)
    length := strconv.itoa(buf[:], len(json))

    return strings.concatenate({
        "Content-Length: ", length, "\r\n",
        "\r\n",
        json,
    })
}

completion_request_message :: proc(id: int, uri: string, line: int, character: int) -> string {
    id_buf := make([dynamic]u8, 16)
    str_id := strconv.itoa(id_buf[:], id)

    json := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"id\": \"", str_id, "\",\n",
        "  \"method\": \"textDocument/completion\",\n",
        "  \"params\": {\n",
        "    \"textDocument\": {\n",
        "      \"uri\": \"", uri, "\"\n",
        "    },\n",
        "    \"position\": {\n",
        "      \"line\": ", strconv.itoa(make([dynamic]u8, 16)[:], line), ",\n",
        "      \"character\": ", strconv.itoa(make([dynamic]u8, 16)[:], character), "\n",
        "    }\n",
        "  }\n",
        "}\n",
    })

    buf := make([dynamic]u8, 32)
    length := strconv.itoa(buf[:], len(json))

    return strings.concatenate({
        "Content-Length: ", length, "\r\n",
        "\r\n",
        json,
    })
}

semantic_tokens_request_message :: proc(id: int, uri: string, line_start: int, line_end: int) -> string {
    id_buf := make([dynamic]u8, 16)
    str_id := strconv.itoa(id_buf[:], id)

    json := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"id\": \"", str_id, "\",\n",
        "  \"method\": \"textDocument/semanticTokens/full\",\n",
        "  \"params\": {\n",
        "    \"textDocument\": {\n",
        "      \"uri\": \"", uri, "\"\n",
        "    }\n",
        "  }\n",
        "}\n",
    })

    buf := make([dynamic]u8, 32)
    length := strconv.itoa(buf[:], len(json))

    return strings.concatenate({
        "Content-Length: ", length, "\r\n",
        "\r\n",
        json,
    })
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