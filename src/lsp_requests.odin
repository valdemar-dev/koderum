#+feature dynamic-literals
package main
import "core:os"
import "core:fmt"
import "core:strings"
import gl "vendor:OpenGL"
import "vendor:glfw"
import "base:runtime"
import "core:unicode/utf8"
import "core:strconv"
import "core:path/filepath"
import ft "../../alt-odin-freetype" 
import ts "../../odin-tree-sitter"    
import "core:time"
import "core:math"

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

text_document_did_save_message :: proc(doc_uri: string) -> string {
    json := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"method\": \"textDocument/didSave\",\n",
        "  \"params\": {\n",
        "    \"textDocument\": {\n",
        "      \"uri\": \"", doc_uri, "\"\n",
        "    }\n",
        "  }\n",
        "}\n"
    }, context.temp_allocator)

    buf := make([dynamic]u8, 32)
    length := strconv.itoa(buf[:], len(json))

    header := strings.concatenate({
        "Content-Length: ", length, "\r\n",
        "\r\n",
        json,
    }, context.temp_allocator)

    delete(buf)
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

/*
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
*/

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
        "    \"capabilities\": {\n",
        "      \"textDocument\": {\n",
        "        \"publishDiagnostics\": {}\n",
        "      }\n",
        "    }\n",
        "  }\n",
        "}\n",
    }, context.temp_allocator)

    len_buf := make([dynamic]u8, 32)
    length := strconv.itoa(len_buf[:], len(json))

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

did_close_message :: proc(uri: string) -> string {
    json := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"method\": \"textDocument/didClose\",\n",
        "  \"params\": {\n",
        "    \"textDocument\": {\n",
        "      \"uri\": \"", uri, "\"\n",
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

completion_item_resolve_request_message :: proc(
    id: int,
    completion_item_json: string,
) -> (msg: string, id_string: string) {
    id_buf := make([dynamic]u8, 16)
    str_id := strconv.itoa(id_buf[:], id)
    defer delete(id_buf)

    json := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"id\": \"", str_id, "\",\n",
        "  \"method\": \"completionItem/resolve\",\n",
        "  \"params\": ", completion_item_json, "\n",
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


goto_definition_request_message :: proc(
    id: int,
    uri: string,
    line: int,
    character: int,
) -> (msg: string, id_string: string) {
    id_buf := make([dynamic]u8, 16)
    str_id := strconv.itoa(id_buf[:], id)
    defer delete(id_buf)

    line_buf := make([dynamic]u8, 12)
    char_buf := make([dynamic]u8, 12)
    str_line := strconv.itoa(line_buf[:], line)
    str_char := strconv.itoa(char_buf[:], character)
    defer delete(line_buf)
    defer delete(char_buf)

    json := strings.concatenate({
        "{\n",
        "  \"jsonrpc\": \"2.0\",\n",
        "  \"id\": \"", str_id, "\",\n",
        "  \"method\": \"textDocument/definition\",\n",
        "  \"params\": {\n",
        "    \"textDocument\": { \"uri\": \"", uri, "\" },\n",
        "    \"position\": { \"line\": ", str_line, ", \"character\": ", str_char, " }\n",
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

