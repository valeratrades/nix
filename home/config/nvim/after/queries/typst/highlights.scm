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

(quote) @markup.quote

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
; Math idents — fallback (low priority, overridden by specific rules below)
; -------------------------------------------------------------------

(formula (ident) @variable)
(attach (ident) @variable)

; -------------------------------------------------------------------
; Math keywords: quantifiers and membership (priority 105 to beat fallback)
; -------------------------------------------------------------------

(formula
  ((ident) @keyword
    (#any-of? @keyword "in" "forall" "exists" "not" "and" "or" "where")
    (#set! priority 105)))

(attach
  ((ident) @keyword
    (#any-of? @keyword "in" "forall" "exists" "not" "and" "or" "where")
    (#set! priority 105)))

; Also in field base position: e.g. if someone writes exists.smth
(field
  ((ident) @keyword
    (#any-of? @keyword "in" "forall" "exists" "not" "and" "or" "where")
    (#set! priority 105)))

; -------------------------------------------------------------------
; Math operators: set ops, relations, big ops, standard functions (priority 105)
; -------------------------------------------------------------------

(formula
  ((ident) @function.builtin
    (#any-of? @function.builtin
      "subset" "supset" "union" "inter" "times" "div" "mod"
      "plus" "minus" "pm" "mp" "dot" "cdot" "ast"
      "cap" "cup" "oplus" "otimes" "ominus"
      "sum" "prod" "integral" "iota" "nabla" "partial" "diff"
      "eq" "neq" "lt" "gt" "leq" "geq" "prec" "succ"
      "approx" "equiv" "sim" "asymp" "prop" "propto"
      "lim" "liminf" "limsup" "sup" "inf" "min" "max"
      "log" "ln" "exp" "sin" "cos" "tan" "det"
      "sqrt" "root" "abs" "norm" "floor" "ceil" "round"
      "arrow" "Arrow" "harpoon" "tilde" "hat" "bar" "vec"
      "therefore" "because" "qed" "compose" "nothing" "emptyset"
      "oo" "infinity"
      )
    (#set! priority 105)))

(attach
  ((ident) @function.builtin
    (#any-of? @function.builtin
      "subset" "supset" "union" "inter" "times" "div" "mod"
      "plus" "minus" "pm" "mp" "dot" "cdot" "ast"
      "cap" "cup" "oplus" "otimes" "ominus"
      "sum" "prod" "integral" "iota" "nabla" "partial" "diff"
      "eq" "neq" "lt" "gt" "leq" "geq" "prec" "succ"
      "approx" "equiv" "sim" "asymp" "prop" "propto"
      "lim" "liminf" "limsup" "sup" "inf" "min" "max"
      "log" "ln" "exp" "sin" "cos" "tan" "det"
      "sqrt" "root" "abs" "norm" "floor" "ceil" "round"
      "arrow" "Arrow" "harpoon" "tilde" "hat" "bar" "vec"
      "therefore" "because" "qed" "compose" "nothing" "emptyset"
      "oo" "infinity"
      )
    (#set! priority 105)))

; Field base position: subset in subset.eq, union in union.big
(field
  ((ident) @function.builtin
    (#any-of? @function.builtin
      "subset" "supset" "union" "inter" "times" "div" "mod"
      "plus" "minus" "pm" "mp" "dot" "cdot" "ast"
      "cap" "cup" "oplus" "otimes" "ominus"
      "sum" "prod" "integral" "iota" "nabla" "partial" "diff"
      "eq" "neq" "lt" "gt" "leq" "geq" "prec" "succ"
      "approx" "equiv" "sim" "asymp" "prop" "propto"
      "lim" "liminf" "limsup" "sup" "inf" "min" "max"
      "log" "ln" "exp" "sin" "cos" "tan" "det"
      "sqrt" "root" "abs" "norm" "floor" "ceil" "round"
      "arrow" "Arrow" "harpoon" "tilde" "hat" "bar" "vec"
      "therefore" "because" "qed" "compose" "nothing" "emptyset"
      "oo" "infinity"
      )
    (#set! priority 105)))

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
; Math field access: .eq, .big — the accessor part
; -------------------------------------------------------------------

(formula
  (field
    field: (ident) @variable.member))

(attach
  (field
    field: (ident) @variable.member))

; -------------------------------------------------------------------
; Subscript/superscript markers
; -------------------------------------------------------------------

(attach "_" @punctuation.special)
(attach "^" @punctuation.special)

; -------------------------------------------------------------------
; Math misc operators
; -------------------------------------------------------------------

(fraction "/" @operator)
(prime) @operator
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
