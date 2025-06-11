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
import ts "../../odin-tree-sitter"
import "core:time"

LanguageServer :: struct {
    lsp_stdin_w : ^os2.File,
    lsp_stdout_r : ^os2.File,
    lsp_server_pid : int,
    
    token_types : []string,
    token_modifiers : []string,
    
    ts_parser: ts.Parser,
    
    colors : map[string]vec4,
    ts_colors : map[string]vec4,
}

Token :: struct {
    line:        i32,
    char:        i32,
    length:      i32,
    color: vec4,
    modifiers:   []string,
    priority: u8,
}

log_unhandled_treesitter_cases := false

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
            server,err := init_syntax_typescript(ext)
            
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
    
    set_buffer_tokens()
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

        type := active_language_server.token_types[token_type_index]

        if type not_in active_language_server.colors {
            fmt.println("Could not find a color for type", type, "whilst attempting to decode semantic tokens.")
        }

        color := active_language_server.colors[type]

        t := Token{
            line = line,
            char = char,
            length = length,
            color = color,
            modifiers = decode_modifiers(token_mod_bitset, token_modifiers),
            priority = 3,
        }
        
        append(&tokens, t)
    }

    return tokens
}

set_buffer_tokens :: proc() {
    if active_language_server == nil {
        return
    }
     
    when ODIN_DEBUG {
        start := time.now()
        prev := start
    }
    
    start_version := active_buffer.version
    
    new_tokens := make([dynamic]Token)
    
    set_buffer_keywords(&new_tokens)
    
    {
        when ODIN_DEBUG {
            now := time.now()
            
            fmt.println("Took", time.diff(prev, now), "to Tree-Sitter the tokens.")
            
            prev = now
        }
    }
    
    active_buffer.tokens = new_tokens
    
    {
        when ODIN_DEBUG {
            now := time.now()
            
            fmt.println("Took", time.diff(prev, now), "to assign tokens.")
            
            prev = now
        }
    }    
}

set_buffer_tokens_threaded :: proc() {
    if active_language_server != nil {
        return
    }
    
    when ODIN_DEBUG {
        start := time.now()
        prev := start
    }
    
    new_tokens := make([dynamic]Token)
    
    append_elems(&new_tokens, ..active_buffer.tokens[:])
    
    start_version := active_buffer.version
    
    //request_full_tokens(active_buffer, &new_tokens)
    
    {
        when ODIN_DEBUG {
            now := time.now()
            
            fmt.println("Took", time.diff(prev, now), "to get LSP tokens.")
            
            prev = now
        }
    }
 
    sort_proc :: proc(token_a: Token, token_b: Token) -> int {
        if token_a.line != token_b.line {
            return int(token_a.line - token_b.line)
        } else if token_a.char != token_b.char {    
            return int(token_a.char - token_b.char)
        }
        
        return int(int(token_b.priority) - int(token_a.priority))
    }
    
    sort.quick_sort_proc(new_tokens[:], sort_proc)
    
    {
        when ODIN_DEBUG {
            now := time.now()
            
            fmt.println("Took", time.diff(prev, now), "to sort buffer tokens.")
            
            prev = now
        }
    }
    
    // cool lag-behind system
    // forces set buffer tokens to catch up to the real buffer
    if start_version == active_buffer.version {
        do_refresh_buffer_tokens = false
        active_buffer.tokens = new_tokens
    }
    
    {
        when ODIN_DEBUG {
            now := time.now()
            prev = now
            
            fmt.println("Took", time.diff(start, now), "to update buffer tokens.")
        }
    }
}

request_full_tokens :: proc(buffer: ^Buffer, tokens: ^[dynamic]Token) {
    lsp_request_id += 1
    
    when ODIN_DEBUG {
        start := time.now()
        prev := start
    }
    
    msg := semantic_tokens_request_message(
        lsp_request_id,
        strings.concatenate({"file://",active_buffer.file_name}),
        0, len(active_buffer.lines)
    )
        
    _, write_err := os2.write(active_language_server.lsp_stdin_w, transmute([]u8)msg)
    
    bytes, read_err := read_lsp_message(active_language_server.lsp_stdout_r, context.allocator)
    
    when ODIN_DEBUG {
        // fmt.println(string(bytes))
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
    
    lsp_tokens := make([dynamic]i32)
    
    for value in data {
        append(&lsp_tokens, i32(value.(f64)))
    }
    
    decoded_tokens := decode_semantic_tokens(
        lsp_tokens[:],
        active_language_server.token_types,
        active_language_server.token_modifiers,
    )
    
    for token,index in decoded_tokens {        
        if int(token.line) > len(active_buffer.lines) - 1 {
            fmt.println("Illegal semantic token. Greater than buffer line length.")
            
            break
        } 
        
        append(tokens, token)
    }
 
    delete(decoded_tokens)
}

request_token_delta :: proc(buffer: ^Buffer, tokens: ^[dynamic]Token) {
    lsp_request_id += 1
    
    msg := semantic_tokens_delta_message(
        lsp_request_id, 
        strings.concatenate({
            "file://",
            buffer.file_name,
        }),
        buffer.token_set_id,
    )

    fmt.println()
}

notify_server_of_change :: proc(
    buffer: ^Buffer,
    start_line: int,
    start_char: int,
    end_line: int,
    end_char: int,
    old_byte_length: int,
    new_end_char: int,
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
    
    if buffer.previous_tree != nil {        
        start_byte,old_end_byte,end_byte := apply_diff(
            buffer,
            start_line, start_char,
            end_line, end_char,
            new_text,
        )
        
        edit := ts.Input_Edit{
            u32(start_byte),
            u32(old_end_byte),
            u32(end_byte),
            ts.Point{},
            ts.Point{},
            ts.Point{},
        }
        
        ts.tree_edit(buffer.previous_tree, &edit)
    }
    
    set_buffer_tokens()
    do_refresh_buffer_tokens = true
}

compute_byte_offset :: proc(content: []u8, target_line: int, target_rune: int) -> int {
    line_count := 0
    byte_off := 0
    total_len := len(content)

    for line_count < target_line {
        if byte_off >= total_len {
            fmt.println("compute_byte_offset: requested line ", target_line, " out of range")
            panic("")
        }
        if content[byte_off] == '\n' {
            line_count += 1
        }
        byte_off += 1
    }

    rune_count := 0
    for rune_count < target_rune {
        if byte_off >= total_len {
            fmt.println("compute_byte_offset: requested rune ", target_rune, " on line ", target_line, " out of range")
            panic("")
        }
        _, width := utf8.decode_rune(content[byte_off:])
        byte_off += width
        rune_count += 1
    }
    return byte_off
}

apply_diff :: proc(
    buffer: ^Buffer,
    start_line, start_char: int,
    end_line, end_char: int,
    new_text: string,
) -> (start_byte: int, old_end_byte: int, new_end_byte: int) {
    start_off := compute_byte_offset(buffer.content, start_line, start_char)
    end_off := compute_byte_offset(buffer.content, end_line, end_char)

    content_len := len(buffer.content)
    if start_off < 0 || start_off > content_len {
        fmt.println("apply_diff: start_off out of range ", start_off, " ", content_len)
        panic("")
    }
    if end_off < 0 || end_off > content_len {
        fmt.println("apply_diff: end_off out of range ", end_off, " ", content_len)
        panic("")
    }
    if start_off > end_off {
        fmt.println("apply_diff: start_off after end_off")
        panic("")
    }

    new_bytes := transmute([]u8)new_text

    dyn := make([dynamic]u8)

    for b in buffer.content[0:start_off] {
        append(&dyn, b)
    }
    for b in new_bytes {
        append(&dyn, b)
    }
    for b in buffer.content[end_off:content_len] {
        append(&dyn, b)
    }

    buffer.content = dyn[:]
    
    return start_off, end_off, start_off + len(new_bytes)
}


Interval :: struct {
    start: i32,
    end:   i32,
}


separate_tokens :: proc(tokens: []Token) -> [dynamic]Token {
    result := make([dynamic]Token)

    prev : Token
    outer: for i in 0..<len(tokens) {
        base       := tokens[i]
        base_start := base.char
        base_end   := base.char + base.length

        intervals := make([dynamic]Interval)
        append(&intervals, Interval{ start = base_start, end = base_end })
    
        if (prev.char == base.char) && (prev.line == base.line) && prev.priority > base.priority {
            prev = base
           
            continue outer
        }

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
            
            prev = base

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
                    color   = base.color,
                    priority = base.priority,
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

semantic_tokens_delta_message :: proc(id: int, uri: string, token_set_id: string) -> string {
    id_buf := make([dynamic]u8, 16)
    str_id := strconv.itoa(id_buf[:], id)

    json := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"id\": \"", str_id, "\",\n",
        "  \"method\": \"textDocument/semanticTokens/delta\",\n",
        "  \"params\": {\n",
        "    \"textDocument\": {\n",
        "      \"uri\": \"", uri, "\"\n",
        "    },\n",
        "    \"previousResultId\": \"", token_set_id, "\"\n",
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

override_node_type :: proc(
    node_type: ^string,
    node: ts.Node, 
    source: []u8,
    start_point,
    end_point: ^ts.Point,
) {
    switch active_buffer.ext {
    case ".ts", ".js":
        override_node_type_ts(node_type, node, source, start_point, end_point)
    }
}


walk_tree :: proc(node: ts.Node, source: []u8, tokens: ^[dynamic]Token, buffer: ^Buffer) {
    node_type := string(ts.node_type(node))
    
    start_point := ts.node_start_point(node)
    end_point   := ts.node_end_point(node)
    
    override_node_type(&node_type, node, source, &start_point, &end_point)
    
    if node_type in active_language_server.ts_colors {
        for row in start_point.row..=end_point.row {
            if int(row) > len(buffer.lines) -1 {
                continue
            }
            
            line := buffer.lines[row]
            line_string := utf8.runes_to_string(line.characters)

            start_col := row == start_point.row ? start_point.col : 0
            end_col   := row == end_point.row   ? end_point.col   : u32(len(line_string))

            start_char := byte_offset_to_rune_index(line_string, int(start_col))
            end_char   := byte_offset_to_rune_index(line_string, int(end_col))

            length := end_char - start_char
            
            if length <= 0 {
                continue
            }
            
            color := active_language_server.ts_colors[node_type]
            append(tokens, Token{
                char     = i32(start_char),
                line     = i32(row),
                length   = i32(length),
                color    = color,
                priority = 0,
            })
        }
    } else if log_unhandled_treesitter_cases == true {
        fmt.println(node_type)
    }
    
    child_count := ts.node_child_count(node)
    for i: u32 = 0; i < child_count; i += 1 {
        child := ts.node_child(node, i)
        walk_tree(child, source, tokens, buffer)
    }
}

get_node_text :: proc(node: ts.Node, source: []u8) -> string {
    start := ts.node_start_byte(node)
    end := ts.node_end_byte(node)
    return string(source[start:end])
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
