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
import "core:sort"

LanguageServer :: struct {
    lsp_stdin_w : ^os2.File,
    lsp_stdout_r : ^os2.File,
    lsp_server_pid : int,
    
    token_types : []string,
    token_modifiers : []string,
}

Token :: struct {
    line:        i32,
    char:        i32,
    length:      i32,
    type:        string,
    modifiers:   []string,
}

color_map : map[string]vec4 = {
    "variable"=BLUE,
    "type"=CYAN,
    "function"=RED,
    "keyword"=ORANGE,
    "property"=PURPLE,
    "comment"=RED,
    "member"=RED,
    "string"=GREEN,
}

/*
NOTE: these are here for reference, just in case we need them.

export enum SemanticTokenTypes {
	namespace = 'namespace',
	/**
	 * Represents a generic type. Acts as a fallback for types which
	 * can't be mapped to a specific type like class or enum.
	 */
	type = 'type',
	class = 'class',
	enum = 'enum',
	interface = 'interface',
	struct = 'struct',
	typeParameter = 'typeParameter',
	parameter = 'parameter',
	variable = 'variable',
	property = 'property',
	enumMember = 'enumMember',
	event = 'event',
	function = 'function',
	method = 'method',
	macro = 'macro',
	keyword = 'keyword',
	modifier = 'modifier',
	comment = 'comment',
	string = 'string',
	number = 'number',
	regexp = 'regexp',
	operator = 'operator',
	/**
	 * @since 3.17.0
	 */
	decorator = 'decorator'
}

export enum SemanticTokenModifiers {
	declaration = 'declaration',
	definition = 'definition',
	readonly = 'readonly',
	static = 'static',
	deprecated = 'deprecated',
	abstract = 'abstract',
	async = 'async',
	modification = 'modification',
	documentation = 'documentation',
	defaultLibrary = 'defaultLibrary'
}
*/


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
    
    do_refresh_buffer_tokens = true
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
    
    _, write_err := os2.write(active_language_server.lsp_stdin_w, transmute([]u8)msg)
    
    bytes, read_err := read_lsp_message(active_language_server.lsp_stdout_r, context.allocator)
        
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

    new_tokens := make([dynamic]Token)
    
    for token,index in decoded_tokens {        
        if int(token.line) > len(active_buffer.lines) - 1 {
            fmt.println("Illegal semantic token. Greater than buffer line length.")
            
            break
        } 
        
        append(&new_tokens, token)
    }
 
    delete(decoded_tokens)
     
    sort_proc :: proc(token_a: Token, token_b: Token) -> int {
        if token_a.line != token_b.line {
            return int(token_a.line - token_b.line)
        }
        return int(token_a.char - token_b.char)
    }

    set_buffer_keywords(&new_tokens)

    sort.quick_sort_proc(new_tokens[:], sort_proc)       
    new_tokens = separate_tokens(new_tokens[:])
    sort.quick_sort_proc(new_tokens[:], sort_proc)

    active_buffer.tokens = new_tokens
 
    do_refresh_buffer_tokens = false
    
    when ODIN_DEBUG {
        fmt.println("Set buffer tokens")
    }
}

notify_server_of_change :: proc(
    buffer: ^Buffer,
    start_line: int,
    start_char: int,
    end_line: int,
    end_char: int,
    new_text: string,
) {
    if active_language_server == nil {
        return
    }
    
    buffer^.version += 1
    
    escaped := escape_json(new_text)

    msg := text_document_did_change_message(
        strings.concatenate({
            "file://",
            buffer.file_name,
        }),
        buffer.version,
        start_line, start_char, end_line, end_char, escaped,
    )
    
    _, write_err := os2.write(active_language_server.lsp_stdin_w, transmute([]u8)msg)
    
    do_refresh_buffer_tokens = true
}

Interval :: struct {
    start: i32,
    end:   i32,
}

separate_tokens :: proc(tokens: []Token) -> [dynamic]Token {
    result := make([dynamic]Token)

    for i in 0..<len(tokens) {
        base       := tokens[i]
        base_start := base.char
        base_end   := base.char + base.length

        intervals := make([dynamic]Interval)
        append(&intervals, Interval{ start = base_start, end = base_end })

        for j := i + 1; j < len(tokens); j += 1 {
            next := tokens[j]
            if next.line != base.line {
                continue
            }

            next_start := next.char
            next_end   := next.char + next.length

            new_intervals := make([dynamic]Interval)

            for k in 0..<len(intervals) {
                iv := intervals[k]

                if next_end <= iv.start || next_start >= iv.end {
                    append(&new_intervals, iv)
                    continue
                }

                if next_start > iv.start {
                    append(&new_intervals, Interval{
                        start = iv.start,
                        end   = next_start,
                    })
                }
                
                if next_end < iv.end {
                    append(&new_intervals, Interval{
                        start = next_end,
                        end   = iv.end,
                    })
                }
            }

            intervals = new_intervals
        }

        for k in 0..<len(intervals) {
            iv      := intervals[k]
            seg_len := iv.end - iv.start
            if seg_len > 0 {
                append(&result, Token{
                    char   = iv.start,
                    length = seg_len,
                    line   = base.line,
                    type   = base.type,
                })
            }
        }
    }

    return result
}


lsp_query_hover :: proc(token_string: string) {
}

set_buffer_keywords :: proc(tokens: ^[dynamic]Token) {
    switch active_buffer.ext {
    case ".js",".ts":
        set_buffer_keywords_ts(tokens)
    }
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

text_document_hover_message :: proc(doc_uri: string, line: int, character: int, id: int) -> string {
    buf := make([dynamic]u8, 32)
    
    id_str := strconv.itoa(buf[:], id)
    
    line_str := strconv.itoa(buf[:], line)
    char_str := strconv.itoa(buf[:], character)

    json := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"id\": ", id_str, ",\n",
        "  \"method\": \"textDocument/hover\",\n",
        "  \"params\": {\n",
        "    \"textDocument\": {\n",
        "      \"uri\": \"", doc_uri, "\"\n",
        "    },\n",
        "    \"position\": {\n",
        "      \"line\": ", line_str, ",\n",
        "      \"character\": ", char_str, "\n",
        "    }\n",
        "  }\n",
        "}\n",
    })

    buf = make([dynamic]u8, 32)
    length := strconv.itoa(buf[:], len(json))

    header := strings.concatenate({
        "Content-Length: ", length, "\r\n",
        "\r\n",
        json,
    })

    delete(buf)
    return header
}

text_document_did_change_message :: proc(doc_uri: string, version: int, start_line: int, start_char: int, end_line: int, end_char: int, new_text: string) -> string {
    buf := [32]u8{}

    version_str := strings.clone(strconv.itoa(buf[:], version), context.temp_allocator)
    
    start_line_str := strings.clone(strconv.itoa(buf[:], start_line), context.temp_allocator)
    start_char_str := strings.clone(strconv.itoa(buf[:], start_char), context.temp_allocator)
    end_line_str := strings.clone(strconv.itoa(buf[:], end_line), context.temp_allocator)
    end_char_str := strings.clone(strconv.itoa(buf[:], end_char), context.temp_allocator)

    json := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"method\": \"textDocument/didChange\",\n",
        "  \"params\": {\n",
        "    \"textDocument\": {\n",
        "      \"uri\": \"", doc_uri, "\",\n",
        "      \"version\": ", version_str, "\n",
        "    },\n",
        "    \"contentChanges\": [\n",
        "      {\n",
        "        \"range\": {\n",
        "          \"start\": { \"line\": ", start_line_str, ", \"character\": ", start_char_str, " },\n",
        "          \"end\": { \"line\": ", end_line_str, ", \"character\": ", end_char_str, " }\n",
        "        },\n",
        "        \"text\": \"", new_text, "\"\n",
        "      }\n",
        "    ]\n",
        "  }\n",
        "}\n"
    })

    buf = [32]u8{}
    length := strconv.itoa(buf[:], len(json))

    header := strings.concatenate({
        "Content-Length: ", length, "\r\n",
        "\r\n",
        json,
    })

    return header
}


get_project_info_message :: proc(id: int) -> string {
    buf := make([dynamic]u8, 32)
    
    id_str := strconv.itoa(buf[:], id)

    json := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"id\": ", id_str, ",\n",
        "  \"method\": \"textDocument/publishDiagnostics\",\n",
        "  \"params\": {\n",
        "  }\n",
        "}\n",
    })

    buf = make([dynamic]u8, 32)
    length := strconv.itoa(buf[:], len(json))

    header := strings.concatenate({
        "Content-Length: ", length, "\r\n",
        "\r\n",
        json,
    })

    delete(buf)
    return header
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

text_document_document_symbol_message :: proc(doc_uri: string, id: int) -> string {
    buf := make([dynamic]u8, 32)
    id_str := strconv.itoa(buf[:], id)

    json := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"id\": ", id_str, ",\n",
        "  \"method\": \"textDocument/documentSymbol\",\n",
        "  \"params\": {\n",
        "    \"textDocument\": {\n",
        "      \"uri\": \"", doc_uri, "\"\n",
        "    }\n",
        "  }\n",
        "}\n",
    })

    delete(buf)
    
    buf = make([dynamic]u8, 32)
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
