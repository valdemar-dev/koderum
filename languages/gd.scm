(comment) @comment

(string) @string
(string_name) @string.special
(node_path) @string.special
(escape_sequence) @escape_sequence

[
  "if"
  "elif"
  "else"
  "for"
  "while"
  "func"
  "class"
  "enum"
  "extends"
  "class_name"
  "signal"
  "var"
  "const"
  "onready"
  "export"
  "setget"
] @keyword

(remote_keyword) @keyword.special
[
  "return"
  "break"
  "continue"
  "pass"
  "breakpoint"
  "match"
  "await"
] @control.flow

(true) @constant.builtin
(false) @constant.builtin
(null) @constant.builtin
(const_statement name: (identifier) @constant)

(identifier) @variable.builtin
(variable_statement name: (identifier) @variable.declaration)
(onready_variable_statement name: (identifier) @variable.declaration)
(export_variable_statement name: (identifier) @variable.declaration)
(setter) @private_field
(getter) @private_field

[
  ";"
  ","
  ":"
  "."
] @punctuation.delimiter

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

(binary_operator op: [
  "and"
  "or"
  "not"
  "in"
  "is"
  "as"
  "&&"
  "||"
  "+"
  "-"
  "*"
  "/"
  "**"
  "%"
  "|"
  "&"
  "^"
  "<<"
  ">>"
  "<"
  "<="
  "=="
  "!="
  ">="
  ">"
] @operator)

(augmented_assignment op: [
  "+="
  "-="
  "*="
  "/="
  "**="
  "%="
  ">>="
  "<<="
  "&="
  "^="
  "|="
] @operator)

(unary_operator op: [
  "not"
  "!"
  "-"
  "+"
  "~"
] @operator)

(function_definition name: (identifier) @function)
(constructor_definition) @function
(lambda name: (identifier) @function)
(call (identifier) @function.method)

(attribute (identifier) @property)
(pair (identifier) @property)
(parameter) @parameter
(typed_parameter) @parameter
(default_parameter) @parameter
(typed_default_parameter) @parameter

(integer) @number
(float) @number

(type) @type
(typed_parameter type: (type) @type.builtin)
(typed_default_parameter type: (type) @type.builtin)


(ERROR) @error