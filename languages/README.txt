Suggested Token Color Values:
    KEYWORD -> 0
    KEYWORD_ALT -> 1
    STRING -> 2
    COMMENTS -> 3
    FUNCTION -> 4
    VARIABLE -> 5
    PROPERTY -> 6
    BUILTIN_TYPE -> 7
    TYPE -> 8
    NUMBER -> 9
    CONTROL_FLOW -> 10
    TEMPLATE_STRING -> 11
    EXTRA -> 12
    EXTRA -> 13
    NAMESPACE -> 14
    
Notes:
    - If the language you're adding support for does not have an LSP server,
      leave lsp_command as an empty directory.
    
Language Struct:
Language :: struct {
    ts_query_src: cstring,
    ts_language: ^ts.Language,
    ts_colors: map[string]vec4,

    lsp_colors: map[string]vec4,
    lsp_working_dir: string,
    lsp_command: []string,
    lsp_install_command: string,

    // Function to call in case you need to manually set a tokens type.
    override_node_type : proc(
        node_type: ^string,
        node: ts.Node, 
        source: []u8,
        start_point,
        end_point: ^ts.Point,
        tokens: ^[dynamic]Token,
        priority: ^u8,
    ),
    
    // Files to look for to determine the root of a project.
    // tsconfig.json, ols.json, etc.    
    project_root_markets: []string,

    // Where the installed parser is located.
    // Parsers are here: .local/share/koderum/parsers/<PARSER>.
    parser_name: string,

    // Used for when compiling the parser.
    // Example: tree-sitter/tree-sitter-typescript/typescript
    parser_subpath: string,

    // Where to download the parser.
    parser_link: string,

    // Eg. tree_sitter_typescript().
    language_symbol_name: string,
    
    // This colour is used when no token is present.
    filler_color: vec4,
}