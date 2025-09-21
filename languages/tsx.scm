; Comments
(comment) @comment
<p>; Strings
(string) @string
(template_string) @string</p>
<p>; Numbers
(number) @number</p>
<p>; Booleans
(true) @constant.builtin.boolean
(false) @constant.builtin.boolean</p>
<p>; Null and undefined
(null) @constant
(undefined) @constant</p>
<p>; Keywords
"abstract" @keyword
"any" @type.builtin
"as" @keyword
"assert" @keyword
"async" @keyword
"await" @keyword
"break" @keyword
"case" @keyword
"catch" @keyword
"class" @keyword
"const" @keyword
"continue" @keyword
"debugger" @keyword
"default" @keyword
"delete" @keyword
"do" @keyword
"else" @keyword
"enum" @keyword
"export" @keyword
"extends" @keyword
"finally" @keyword
"for" @keyword
"from" @keyword
"function" @keyword
"if" @keyword
"implements" @keyword
"import" @keyword
"in" @keyword
"instanceof" @keyword
"interface" @keyword
"let" @keyword
"new" @keyword
"of" @keyword
"package" @keyword
"private" @keyword
"protected" @keyword
"public" @keyword
"return" @keyword
"static" @keyword
"super" @variable.builtin
"switch" @keyword
"this" @variable.builtin
"throw" @keyword
"try" @keyword
"type" @keyword
"typeof" @keyword
"var" @keyword
"void" @type.builtin
"while" @keyword
"with" @keyword
"yield" @keyword</p>
<p>; Operators
"--" @operator
"-" @operator
"-=" @operator
"!" @operator
"!=" @operator
"%" @operator
"%=" @operator
"&#x26;" @operator
"&#x26;&#x26;" @operator
"&#x26;=" @operator
"<em>" @operator
"</em>=" @operator
"+" @operator
"++" @operator
"+=" @operator
"/" @operator
"/=" @operator
"&#x3C;&#x3C;" @operator
"&#x3C;&#x3C;=" @operator
"&#x3C;" @operator
"&#x3C;=" @operator
"=" @operator
"==" @operator
">" @operator
">=" @operator
">>" @operator
">>=" @operator
"?" @operator
"??" @operator
"??=" @operator
"^" @operator
"^=" @operator
"|" @operator
"|=" @operator
"||" @operator
"~" @operator
"..." @operator
"as" @operator
"keyof" @operator
"infer" @operator
"is" @operator</p>
<p>; Punctuation and delimiters
"." @delimiter
";" @delimiter
"," @delimiter</p>
<p>"(" @punctuation
")" @punctuation
"{" @punctuation
"}" @punctuation
"[" @punctuation
"]" @punctuation
"&#x3C;" @punctuation
">" @punctuation</p>
<p>; Identifiers
(identifier) @variable</p>
<p>((identifier) @constant
(#match? @constant "^[A-Z][A-Z0-9_]*$"))</p>
<p>; Types
(type_identifier) @type
(predefined_type) @type.builtin</p>
<p>; Functions
(function_declaration name: (identifier) @function)
(method_definition name: (property_identifier) @function)
(arrow_function parameters: (formal_parameters) . body: (_) @function)</p>
<p>; Parameters
(formal_parameters (identifier) @parameter)</p>
<p>; JSX
(jsx_element
open_tag: (jsx_opening_element
name: (<em>) @tag))
(jsx_element
close_tag: (jsx_closing_element
name: (</em>) @tag))
(jsx_self_closing_element name: (<em>) @tag)
(jsx_attribute (property_identifier) @property)
(jsx_expression (</em>) @embedded)</p>
<p>; Decorators
(decorator "@" @punctuation.special (identifier) @attribute)