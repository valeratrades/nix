; functions
(function_definition) @function.outer

(function_definition
  body: (braced_block
    .
    "{"
    _+ @function.inner
    "}"))

(function_definition
  body: [
    (indented_block)
    (block_indent)
  ] @function.inner)

; type definitions. `Foo := class {...}` is an assignment whose right side is the
; type expression, so the outer object has to reach up to the binding.
(assignment_expression
  right: [
    (class_expression)
    (struct_expression)
    (interface_expression)
    (enum_expression)
    (module_expression)
  ]) @class.outer

(class_expression
  (braced_block
    .
    "{"
    _+ @class.inner
    "}"))

(class_expression
  [
    (indented_block)
    (block_indent)
  ] @class.inner)

(struct_expression
  (braced_block
    .
    "{"
    _+ @class.inner
    "}"))

(struct_expression
  [
    (indented_block)
    (block_indent)
  ] @class.inner)

(interface_expression
  (braced_block
    .
    "{"
    _+ @class.inner
    "}"))

(interface_expression
  [
    (indented_block)
    (block_indent)
  ] @class.inner)

(enum_expression
  (braced_block
    .
    "{"
    _+ @class.inner
    "}"))

(enum_expression
  [
    (indented_block)
    (block_indent)
  ] @class.inner)

(module_expression
  (braced_block
    .
    "{"
    _+ @class.inner
    "}"))

(module_expression
  [
    (indented_block)
    (block_indent)
  ] @class.inner)

; parameters / arguments
(argument_list
  (argument) @parameter.inner)

(argument_list
  (argument) @parameter.outer)

; loops
[
  (for_expression)
  (loop_expression)
] @loop.outer

(for_expression
  [
    (braced_block)
    (indented_block)
    (block_indent)
  ] @loop.inner)

(loop_expression
  [
    (braced_block)
    (indented_block)
    (block_indent)
  ] @loop.inner)

; conditionals
[
  (if_expression)
  (case_expression)
] @conditional.outer

(if_expression
  [
    (braced_block)
    (indented_block)
    (block_indent)
  ] @conditional.inner)

(case_expression
  [
    (braced_block)
    (indented_block)
    (block_indent)
  ] @conditional.inner)

; comments
[
  (line_comment)
  (block_comment)
] @comment.outer
