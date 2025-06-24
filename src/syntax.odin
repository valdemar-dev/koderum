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

    completion_trigger_runes : []rune,
    
    ts_parser: ts.Parser,
    
    colors : map[string]vec4,
    ts_colors : map[string]vec4,

    name : string,

    override_node_type: proc(
        node_type: ^string,
        node: ts.Node, 
        source: []u8,
        start_point,
        end_point: ^ts.Point,
        tokens: ^[dynamic]Token,  
        priority: ^u8,
    ),
    
    parse_tree : proc(first_line, last_line: int) -> ts.Tree,
    set_tokens : proc(first_line, last_line: int, tree_ptr: ^ts.Tree),
    set_lsp_tokens : proc(buffer: ^Buffer, lsp_tokens: []Token),
}

Token :: struct {
    line: i32,
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

    defer {
        init_message_thread()
    }
    
    switch ext {
    case ".js",".ts":
        if ext not_in language_servers {
            init_syntax_typescript(ext)
        } else {
            active_language_server = language_servers[ext]
        }
    case ".odin":
        if ext not_in language_servers {
            server,err := init_syntax_odin(ext)
            
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
    
    escaped := escape_json(string(active_buffer.content[:]))

    defer delete(escaped)
    
    msg := did_open_message(
        strings.concatenate({"file://",active_buffer.file_name}, context.temp_allocator),
        "typescript",
        1,
        escaped,
    )

    defer delete(msg)

    send_lsp_message(msg, "") 

    active_language_server.parse_tree(0, len(active_buffer.lines))
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

        type := &active_language_server.token_types[token_type_index]

        color := &active_language_server.colors[type^]

        if color == nil {
            when ODIN_DEBUG {
                /*
                fmt.println(
                    "Warning: Missing LSP-Token Colour for Node Type",
                    type^, 
                )
                */
            }

            continue
        }

        t := Token{
            line = line,
            char = char,
            length = length,
            color = color^,
            modifiers = decode_modifiers(token_mod_bitset, token_modifiers),
            priority = 0,
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
    
    active_language_server.parse_tree(active_buffer.first_drawn_line, active_buffer.last_drawn_line)

    {
        when ODIN_DEBUG {
            now := time.now()
            
            fmt.println("Took", time.diff(start, now), "to set single-threaded buffer tokens.")
            
            prev = now
        }
    }    
}

set_buffer_tokens_threaded :: proc() {
    if active_language_server == nil {
        return
    } 

    do_refresh_buffer_tokens = false
  
    start_version := new(int)
    start_version^ = active_buffer.version

    lsp_request_id += 1 
    
    msg,req_id_string := semantic_tokens_request_message(
        lsp_request_id,
        strings.concatenate({"file://",active_buffer.file_name}, context.temp_allocator),
        0, len(active_buffer.lines)
    )

    defer delete(msg)
    defer delete(req_id_string)

    send_lsp_message(
        msg,
        req_id_string,
        handle_response,
        rawptr(start_version),
    )

    new_tree := active_language_server.parse_tree(0, len(active_buffer.lines))
    // active_language_server.set_tokens(0, len(active_buffer.lines), &new_tree)

    ts.tree_delete(new_tree)

    handle_response :: proc(response: json.Object, data: rawptr) {
        start_version_ptr := (cast(^int)data)

        start_version := (start_version_ptr^)

        defer free(data)

        obj,ok := response["result"].(json.Object)
        
        if !ok {
            panic("Malformed json in set_buffer_tokens")
        }
        
        obj_data,data_ok := obj["data"].(json.Array)
        
        if !data_ok {
            panic("Malformed json in set_buffer_tokens")
        }
        
        lsp_tokens := make([dynamic]i32)
        defer delete(lsp_tokens)

        for value in obj_data {
            append(&lsp_tokens, i32(value.(f64)))
        }

        decoded_tokens := decode_semantic_tokens(
            lsp_tokens[:],
            active_language_server.token_types,
            active_language_server.token_modifiers,  
        )
       
        assert(active_language_server != nil)
        active_language_server.set_lsp_tokens(active_buffer, decoded_tokens[:])

        if start_version != active_buffer.version {
            do_refresh_buffer_tokens = true
        } 

        delete(decoded_tokens)
    }
}

notify_server_of_change :: proc(
    buffer: ^Buffer,

    // TS STUFF
    start_byte: int,
    end_byte: int,
    
    // LSP STUFF
    start_line: int,
    start_char: int,
    end_line: int,
    end_char: int,

    new_text: []u8,
) {
    if active_language_server == nil {
        return
    }
    
    buffer^.version += 1
    
    escaped := escape_json(string(new_text))
    defer delete(escaped)

    msg := text_document_did_change_message(
        strings.concatenate({
            "file://",
            buffer.file_name,
        }, context.temp_allocator),
        buffer.version,
        start_line, start_char, end_line, end_char, escaped,
    )

    defer delete(msg)
    
    _, write_err := os2.write(active_language_server.lsp_stdin_w, transmute([]u8)msg)
  
    if buffer.previous_tree != nil {        
        new_end_byte := start_byte + len(new_text)

        remove_range(&buffer.content, start_byte, end_byte)
        inject_at(&buffer.content, start_byte, ..new_text)        

        edit := ts.Input_Edit{
            u32(start_byte),
            u32(end_byte),
            u32(new_end_byte),
            ts.Point{},
            ts.Point{},
            ts.Point{},
        }
        
        ts.tree_edit(buffer.previous_tree, &edit)
    }
    
    set_buffer_tokens()

    do_refresh_buffer_tokens = true
}

compute_byte_offset :: proc(buffer: ^Buffer, line: int, rune_index: int) -> int {
    byte_offset := 0
    for i in 0..<line {
        byte_offset += len(buffer.lines[i].characters[:])
        byte_offset += 1
    }

    line_chars := buffer.lines[line].characters[:]
    pos := utf8.rune_offset(string(line_chars), rune_index)

    if pos == -1 {
        byte_offset += len(line_chars)
    } else {
        byte_offset += pos
    }

    return byte_offset
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
    buf := make([dynamic]u8, 32)

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
    }, context.temp_allocator)

    delete(buf)

    buf = make([dynamic]u8, 32)
    length := strconv.itoa(buf[:], len(json))

    header := strings.concatenate({
        "Content-Length: ", length, "\r\n",
        "\r\n",
        json,
    }, context.temp_allocator)

    defer delete(buf)

    return strings.clone(header)
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
    }, context.temp_allocator)

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
    }, context.temp_allocator)

    len_buf := make([dynamic]u8, 32)

    length := (strconv.itoa(len_buf[:], len(json)))

    defer delete(buf)
    defer delete(len_buf)

    return strings.concatenate({
        "Content-Length: ", length, "\r\n",
        "\r\n",
        json,
    })
}

did_open_message :: proc(uri: string, languageId: string, version: int, text: string) -> string {
    version_buf := make([dynamic]u8, 16)
    defer delete(version_buf)

    json := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"method\": \"textDocument/didOpen\",\n",
        "  \"params\": {\n",
        "    \"textDocument\": {\n",
        "      \"uri\": \"", uri, "\",\n",
        "      \"languageId\": \"", languageId, "\",\n",
        "      \"version\": ", strconv.itoa(version_buf[:], version), ",\n",
        "      \"text\": \"", text, "\"\n",
        "    }\n",
        "  }\n",
        "}\n",
    }, context.temp_allocator)

    buf := make([dynamic]u8, 32)
    defer delete(buf)
    length := strconv.itoa(buf[:], len(json))

    return strings.concatenate({
        "Content-Length: ", length, "\r\n",
        "\r\n",
        json,
    })
}

completion_request_message :: proc(
    id: int,
    uri: string,
    line: int,
    character: int,

    trigger_kind: string,
    trigger_character: string,
) -> (msg, id_str: string) {
    id_buf := make([dynamic]u8, 16)
    str_id := strconv.itoa(id_buf[:], id)
    defer delete(id_buf)

    line_buf := make([dynamic]u8, 16)
    char_buf := make([dynamic]u8, 16)
    defer delete(line_buf)
    defer delete(char_buf)

    line_str := strconv.itoa(line_buf[:], line)
    char_str := strconv.itoa(char_buf[:], character)

    body := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"id\": \"", str_id, "\",\n",
        "  \"method\": \"textDocument/completion\",\n",
        "  \"params\": {\n",
        "    \"textDocument\": {\n",
        "      \"uri\": \"", uri, "\"\n",
        "    },\n",
        "    \"position\": {\n",
        "      \"line\": ", line_str, ",\n",
        "      \"character\": ", char_str, "\n",
        "    },\n",
        "    \"context\": {\n",
        "      \"triggerKind\": ", trigger_kind
    }, context.temp_allocator)

    if trigger_kind == "2" {
        body = strings.concatenate({
            body,
            ",\n",
            "      \"triggerCharacter\": \"", trigger_character, "\""
        }, context.temp_allocator)
    }

    body = strings.concatenate({body, "\n    }\n  }\n}\n"}, context.temp_allocator)

    len_buf := make([dynamic]u8, 32)
    defer delete(len_buf)

    length := strconv.itoa(len_buf[:], len(body))

    final := strings.concatenate({
        "Content-Length: ", length, "\r\n",
        "\r\n",
        body
    })

    return (final), strings.clone(str_id)
}

get_autocomplete_hits :: proc(line: int, character: int, trigger_kind: string, trigger_character: string,) {
    if active_language_server == nil {
        return
    }

    lsp_request_id += 1
    selected_completion_hit = 0

    msg, req_id_string := completion_request_message(
        lsp_request_id,
        strings.concatenate({
            "file://",
            active_buffer.file_name,
        }, context.temp_allocator),
        line,
        character,
        trigger_kind,
        trigger_character,
    )

    defer delete(msg)
    defer delete(req_id_string)
    defer delete(trigger_character)

    send_lsp_message(
        msg,
        req_id_string,
        handle_response,
    )

    handle_response :: proc(response: json.Object, data: rawptr) {
        free(data)

        result,result_ok := response["result"].(json.Object)
        if !result_ok {
            panic("failed to do anythin:?+++++++++")
        }
        items,ok := result["items"].(json.Array)

        if !ok {
            panic("Failed")
        }

        new_hits := make([dynamic]CompletionHit)

        /*
        sort_proc :: proc(a: json.Value, b: json.Value) -> int {
            a_sort := a.(json.Object)["sortText"].(string)
            b_sort := b.(json.Object)["sortText"].(string)

            if a_sort == b_sort {
                a_label := a.(json.Object)["label"].(string)
                b_label := b.(json.Object)["label"].(string)

                if a_label < b_label {
                    return -1
                } else if a_label > b_label {
                    return 1
                }
                return 0
            }

            if a_sort < b_sort {
                return -1
            } else {
                return 1
            }
        }

        sort.quick_sort_proc(items[:], sort_proc)
        */

        cur_line := active_buffer.lines[buffer_cursor_line]
        line_string := string(cur_line.characters[:])

        byte_offset := utf8.rune_offset(line_string, buffer_cursor_char_index)
        if byte_offset == -1 {
            byte_offset = len(line_string)
        }

        last_delimiter_byte := 0

        for char, byte in line_string {
            if byte == byte_offset {
                break
            }

            if rune_in_arr(char, delimiter_runes) {
                last_delimiter_byte = byte+1
            }
        }

        completion_filter_token = line_string[last_delimiter_byte:byte_offset]
        for item in items {
            label, label_ok := item.(json.Object)["label"].(string)
            documentation, documentation_ok := item.(json.Object)["documentation"].(string)

            hit := CompletionHit{
                label=strings.clone(label),
            }

            if documentation_ok {
                hit.documentation = strings.clone(documentation)
            }

            if len(completion_filter_token) > 0 {
                if strings.contains(label, completion_filter_token) == false {
                    continue
                }

                if label == completion_filter_token {
                    inject_at(&new_hits, 0, hit)

                    continue
                }
            }

            append(&new_hits, hit)
        }

        for &hit in completion_hits {
            delete(hit.detail)
            delete(hit.documentation)
            delete(hit.insertText)
            delete(hit.label)
        }

        delete(completion_hits)

        completion_hits = new_hits
    }

}

semantic_tokens_request_message :: proc(
    id: int,
    uri: string,
    line_start: int,
    line_end: int,
) -> (msg: string, id_string: string) {
    id_buf := make([dynamic]u8, 16)
    str_id := strconv.itoa(id_buf[:], id)

    defer delete(id_buf)

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
    }, context.temp_allocator)

    buf := make([dynamic]u8, 32)

    length := strconv.itoa(buf[:], len(json))

    defer delete(buf)

    return strings.concatenate({
        "Content-Length: ", length, "\r\n",
        "\r\n",
        json,
    }), strings.clone(str_id)
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

@(private="package")
is_delimiter_rune :: proc(r: rune) -> bool {
    for delimiter in delimiter_runes {
        if r == delimiter do return true
    }

    return false
}

