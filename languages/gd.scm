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
  "match"
  "await"
] @control.flow

(true) @constant.builtin
(false) @constant.builtin
(null) @constant.builtin

(identifier) @variable.builtin
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

[
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
  "not"
  "!"
  "-"
  "+"
  "~"
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
  "="
] @operator

(constructor_definition) @function
(function_definition) @function
(call) @function

(attribute (identifier) @property)
(pair (identifier) @property)

(integer) @number
(float) @number

(type) @type

(ERROR) @error