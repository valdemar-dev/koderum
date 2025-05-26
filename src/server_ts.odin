#+feature dynamic-literals
#+private file
package main

import "core:os/os2"
import "core:fmt"
import "core:os"
import "core:strings"
import fp "core:path/filepath"
import "core:encoding/json"

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
