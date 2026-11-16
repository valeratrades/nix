; overrides upstream: its `@class` is the heading line alone, here it is the whole section

(list_item) @function.outer

(list_item
  (paragraph
    (inline) @function.inner))

(section) @class.outer

(section
  [
    (atx_heading)
    (setext_heading)
  ]
  .
  (_)+ @class.inner) ; a trailing `.` anchor makes the `+` match only the last child

(fenced_code_block
  (code_fence_content) @block.inner) @block.outer

[
  (paragraph)
  (list)
] @block.outer
