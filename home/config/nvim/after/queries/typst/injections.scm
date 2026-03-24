; Typst injections — standalone (mirrors highlights.scm rationale:
; nvim-treesitter main branch doesn't add runtime/ to rtp for query resolution)

((comment) @injection.content
  (#set! injection.language "comment"))

(raw_blck
  (ident) @injection.language
  (blob) @injection.content)
