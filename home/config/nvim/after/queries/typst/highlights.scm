; Complete typst highlights — standalone (upstream extends broken due to
; nvim-treesitter main branch not adding runtime/ to rtp for query resolution)

; ===================================================================
; Punctuation
; ===================================================================

"#" @punctuation.special

[":" ";" ","] @punctuation.delimiter

["(" ")" "{" "}" "[" "]"] @punctuation.bracket

; ===================================================================
; Code-mode keywords
; ===================================================================

["import" "include"] @keyword.import

["let" "set" "show"] @keyword

["for" "while"] @keyword.repeat

(flow
  "break" @keyword.repeat)

(flow
  "continue" @keyword.repeat)

["if" "else"] @keyword.conditional

(for
  "in" @keyword.repeat)

(return
  "return" @keyword.return)

(context
  "context" @keyword)

; ===================================================================
; Code-mode operators
; ===================================================================

["-" "+" "*" "/" "==" "!=" "<" "<=" ">" ">=" "=" "in"] @operator

["and" "or" "not"] @keyword.operator

(lambda
  "=>" @punctuation.delimiter)

(elude
  ".." @operator)

; ===================================================================
; Code-mode literals
; ===================================================================

(number) @number
(string) @string
(bool) @boolean
(none) @constant.builtin
(auto) @constant.builtin

(unit) @type

; ===================================================================
; Code-mode identifiers & variables
; ===================================================================

(ident) @variable

(let
  pattern: (ident) @variable)

(for
  pattern: (ident) @variable)

(assign
  pattern: (ident) @variable)

(let
  (call
    item: (ident) @function))

(let
  (call
    (group
      (ident) @variable.parameter)))

(lambda
  pattern: (group
    (ident) @variable.parameter))

(call
  item: (ident) @function.call)

(tagged
  field: (ident) @variable.member)

(field
  field: (ident) @variable.member)

(wildcard) @character.special

(binding
  (ident) @variable)

; ===================================================================
; Markup — text mode
; ===================================================================

(text) @spell

(heading
  "=" @markup.heading.1) @markup.heading.1

(heading
  "==" @markup.heading.2) @markup.heading.2

(heading
  "===" @markup.heading.3) @markup.heading.3

(heading
  "====" @markup.heading.4) @markup.heading.4

(heading
  "=====" @markup.heading.5) @markup.heading.5

(heading
  "======" @markup.heading.6) @markup.heading.6

(strong) @markup.strong
(emph) @markup.italic

(item
  ["-" "+"] @markup.list)

(term
  "/" @markup.list)

(term
  term: (_) @markup.strong)

(escape) @string.escape

; quotes inherit parent text color — coloring them stands out too much

(linebreak) @punctuation.special

((url) @markup.link.url
  (#set! @markup.link.url url @markup.link.url))

(call
  item: (ident) @_link
  (#eq? @_link "link")
  (group
    .
    (string) @markup.link.url
    (#offset! @markup.link.url 0 1 0 -1)
    (#set! @markup.link.url url @markup.link.url)))

; ===================================================================
; Raw / code blocks
; ===================================================================

(raw_span) @markup.raw

(raw_blck) @markup.raw

(raw_blck
  lang: (ident) @label)

(raw_blck
  (blob) @markup.raw.block)

; ===================================================================
; References & labels
; ===================================================================

(label) @markup.link.label
(ref) @markup.link

; ===================================================================
; Math mode
; ===================================================================

(math) @markup.math

; $ / $$ delimiters — highlighted separately from formula body
((math
  "$" @punctuation.delimiter.math)
  (#set! priority 105))

; -------------------------------------------------------------------
; Math punctuation-symbols (the `symbol` node type): , ; < > + - = :
; -------------------------------------------------------------------

(formula (symbol) @operator)
(attach (symbol) @operator)

; -------------------------------------------------------------------
; Math shorthands: =>, <=>, ->, <-, :=, ~, ...
; -------------------------------------------------------------------

(formula (shorthand) @operator)
(attach (shorthand) @operator)

; -------------------------------------------------------------------
; Math variables (single letters): x, y, A, B
; -------------------------------------------------------------------

(formula (letter) @variable)
(attach (letter) @variable)
(apply (letter) @variable)

; -------------------------------------------------------------------
; Math idents — multi-letter idents in math are almost always typst
; symbols (forall, subset, union, epsilon, etc). Single-letter names
; use the `letter` node type instead. User-defined names in math go
; through call/apply which have their own rules above.
; -------------------------------------------------------------------

(formula (ident) @constant.builtin)
(attach (ident) @constant.builtin)

; -------------------------------------------------------------------
; Number-like sets: RR, QQ, NN, ZZ, CC, etc. (all-caps 2+ letters)
; -------------------------------------------------------------------

(formula
  ((ident) @type.builtin
    (#lua-match? @type.builtin "^%u%u+$")
    (#set! priority 105)))

(attach
  ((ident) @type.builtin
    (#lua-match? @type.builtin "^%u%u+$")
    (#set! priority 105)))

(field
  ((ident) @type.builtin
    (#lua-match? @type.builtin "^%u%u+$")
    (#set! priority 105)))

; -------------------------------------------------------------------
; Greek letters: distinct from regular variables
; -------------------------------------------------------------------

(formula
  ((ident) @variable.parameter
    (#any-of? @variable.parameter
      "alpha" "beta" "gamma" "delta" "epsilon" "zeta" "eta" "theta"
      "iota" "kappa" "lambda" "mu" "nu" "xi" "omicron" "pi" "rho"
      "sigma" "tau" "upsilon" "phi" "chi" "psi" "omega"
      "Alpha" "Beta" "Gamma" "Delta" "Epsilon" "Zeta" "Eta" "Theta"
      "Iota" "Kappa" "Lambda" "Mu" "Nu" "Xi" "Omicron" "Pi" "Rho"
      "Sigma" "Tau" "Upsilon" "Phi" "Chi" "Psi" "Omega"
      "ell" "hbar" "planck"
      )
    (#set! priority 105)))

(attach
  ((ident) @variable.parameter
    (#any-of? @variable.parameter
      "alpha" "beta" "gamma" "delta" "epsilon" "zeta" "eta" "theta"
      "iota" "kappa" "lambda" "mu" "nu" "xi" "omicron" "pi" "rho"
      "sigma" "tau" "upsilon" "phi" "chi" "psi" "omega"
      "Alpha" "Beta" "Gamma" "Delta" "Epsilon" "Zeta" "Eta" "Theta"
      "Iota" "Kappa" "Lambda" "Mu" "Nu" "Xi" "Omicron" "Pi" "Rho"
      "Sigma" "Tau" "Upsilon" "Phi" "Chi" "Psi" "Omega"
      "ell" "hbar" "planck"
      )
    (#set! priority 105)))

; -------------------------------------------------------------------
; Math function application: f(x), cal(A), sqrt(x)
; -------------------------------------------------------------------

(apply
  item: (_) @function.call)

; -------------------------------------------------------------------
; Math field access: subset.eq, union.big
; Base ident (subset, union) matches the bare symbol color.
; Accessor (.eq, .big) gets @variable.member.
; -------------------------------------------------------------------

(formula
  (field
    (ident) @constant.builtin))

(attach
  (field
    (ident) @constant.builtin))

(formula
  (field
    field: (ident) @variable.member
    (#set! priority 105)))

(attach
  (field
    field: (ident) @variable.member
    (#set! priority 105)))

; -------------------------------------------------------------------
; Subscript/superscript markers
; -------------------------------------------------------------------

(attach "_" @punctuation.special)
(attach "^" @punctuation.special)

; -------------------------------------------------------------------
; Math misc operators
; -------------------------------------------------------------------

(fraction "/" @operator)
(prime (letter) @variable)
(fac "!" @operator)
(align) @punctuation.special

; -------------------------------------------------------------------
; Math literals
; -------------------------------------------------------------------

(formula (string) @string)
(formula (number) @number)
(attach (number) @number)

; ===================================================================
; Comments
; ===================================================================

(comment) @comment @spell
