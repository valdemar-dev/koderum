(ERROR) @error

["meta"] @property
(property_identifier) @property

(function_expression
  name: (identifier) @function)
(function_declaration
  name: (identifier) @function)
(method_definition
  name: (property_identifier) @function.method)

(pair
  key: (property_identifier) @function.method
  value: [(function_expression) (arrow_function)])

(assignment_expression
  left: (member_expression
    property: (property_identifier) @function.method)
  right: [(function_expression) (arrow_function)])

(variable_declarator
  name: (identifier) @function
  value: [(function_expression) (arrow_function)])

(assignment_expression
  left: (identifier) @function
  right: [(function_expression) (arrow_function)])

(call_expression
  function: (identifier) @function)

(call_expression
  function: (member_expression
    property: (property_identifier) @function.method))

([
    (identifier)
    (shorthand_property_identifier)
    (shorthand_property_identifier_pattern)
 ] @constant
 (#match? @constant "^[A-Z_][A-Z\\d_]+$"))

(escape_sequence) @escape_sequence
(this) @variable.builtin
(super) @variable.builtin

[
  (true)
  (false)
  (null)
  (undefined)
] @constant.builtin

(comment) @comment

(template_string
 (string_fragment) @string)

(template_literal_type
 (string_fragment) @string)


(private_property_identifier) @private_field

(formal_parameters (required_parameter (identifier) @parameter))

(string) @string

(regex) @string.special
(number) @number

[
  ";"
  (optional_chain)
  "."
  ","
] @punctuation.delimiter

[
  "-"
  "--"
  "-="
  "+"
  "++"
  "+="
  "*"
  "*="
  "**"
  "**="
  "/"
  "/="
  "%"
  "%="
  "<"
  "<="
  "<<"
  "<<="
  "="
  "=="
  "==="
  "!"
  "!="
  "!=="
  "=>"
  ">"
  ">="
  ">>"
  ">>="
  ">>>"
  ">>>="
  "~"
  "^"
  "&"
  "|"
  "^="
  "&="
  "|="
  "&&"
  "-?:"
  "?"
  "||"
  "??"
  "&&="
  "||="
  "??="
  ":"
  "@"
  "..."
] @operator

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
  "${"
]  @punctuation.bracket

[
  "as"
  "class"
  "const"
  "continue"
  "debugger"
  "delete"
  "export"
  "extends"
  "from"
  "function"
  "get"
  "import"
  "in"
  "instanceof"
  "new"
  "return"
  "set"
  "static"
  "target"
  "typeof"
  "void"
  "yield"
] @keyword

[
  "var"
  "let"
] @variable.declaration

[
  "while"
  "if"
  "else"
  "break"
  "throw"
  "with"
  "catch"
  "finally"
  "case"
  "switch"
  "try"
  "do"
  "default"
  "of"
  "for"
] @control.flow

[
  "async"
  "await"
] @async

[
    "global"
    "module"
    "infer"
    "extends"
    "keyof"
    "as"
    "asserts"
    "is"
] @keyword.special

(type_identifier) @type
(predefined_type) @type.builtin

;((identifier) @type
; (#match? @type "^[A-Z]"))

(type_arguments
  "<" @punctuation.bracket
  ">" @punctuation.bracket)

(required_parameter (identifier) @variable.parameter)
(optional_parameter (identifier) @variable.parameter)

[ "abstract"
  "declare"
  "enum"
  "export"
  "implements"
  "interface"
  "keyof"
  "namespace"
  "private"
  "protected"
  "public"
  "type"
  "readonly"
  "override"
  "satisfies"
] @keyword

["`"] @string