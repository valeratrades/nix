; `indented_block`/`block_indent` come from the grammar's external scanner
; (Verse's offside rule); treating them as ordinary indent scopes is what makes
; `=`- and `:`-introduced bodies indent without braces.
[
  (braced_block)
  (indented_block)
  (block_indent)
  (call_expression)
  (array_literal)
  (map_literal)
  (option_literal)
  (tuple_expression)
  (supertype_clause)
] @indent.begin

(braced_block
  "}" @indent.end)

[
  ")"
  "]"
  "}"
] @indent.branch

[
  (line_comment)
  (block_comment)
  (string)
] @indent.ignore
