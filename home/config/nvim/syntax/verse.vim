" Verse (Epic Games). Regex syntax rather than treesitter on purpose: both public
" tree-sitter-verse grammars grow unboundedly on ~3% of real Verse (a 3-line snippet
" from the Book of Verse drove Unoqwy's parser to 3.9GB in 27s). See README.md.
" Keyword sets track Epic's own Pygments lexer in verselang/book.
"
" Definition order is load-bearing: on a tie at the same start column vim prefers the
" item defined last, so `<public>` and `/Verse.org/...` must come after verseOperator
" or its bare `<` and `/` swallow their first character.

if exists("b:current_syntax")
	finish
endif

syn case match

syn keyword verseKeyword if then else for do block loop case return break continue
syn keyword verseKeyword yield spawn sync race branch defer where when while over of
syn keyword verseKeyword is in to using array option map tuple set var live ref Self
syn keyword verseStructure module interface class struct enum
syn keyword verseType int float string logic char char32 any void comparable rational
syn keyword verseType type task event weak_map
syn keyword verseBoolean true false
syn keyword verseOperatorWord and or not

syn match verseOperator ":=\|=>\|->\|\.\.\|[+\-*/]=\|<>\|<=\|>=\|[+\-*/%<>=?^&|]"

syn match verseNumber "\<[0-9][0-9_]*\>"
syn match verseNumber "\<0b[01_]\+\>"
syn match verseNumber "\<0o[0-7_]\+\>"
syn match verseNumber "\<0x[0-9a-fA-F_]\+\>"
syn match verseFloat "\<[0-9][0-9_]*\.[0-9_]*\%([eE][+-]\?[0-9]\+\)\?"
syn match verseFloat "\<[0-9][0-9_]*[eE][+-]\?[0-9]\+\>"

" Definition heads: `Foo(` and `Foo<spec>(`
syn match verseFunction "\<\h\w*\ze\s*\%(<[^>]*>\)\?\s*("

" `using { /Verse.org/Simulation }`
syn match versePath "/\h[[:alnum:]_.]*\%(/[[:alnum:]_.]\+\)*"

" `<public>`, `<decides>`, `<attribute{...}>`
syn match verseSpecifier "<\w\+\%({[^}]*}\)\?>"
syn match verseDecorator "@\h\w*"

syn match verseEscape "\\." contained
syn region verseInterp matchgroup=verseInterpDelim start="{" end="}" contained contains=TOP
syn match verseCharacter "'\%(\\.\|[^'\\]\)*'"
syn region verseString start=+"+ skip=+\\.+ end=+"+ contains=verseEscape,verseInterp,verseBlockComment,@Spell

" Comments last, and so highest priority: `<#` must beat the `#` that starts one column
" later, and block comments nest.
syn match verseLineComment "#.*$" contains=@Spell
syn region verseBlockComment start="<#" end="#>" contains=verseBlockComment,@Spell

hi def link verseKeyword Keyword
hi def link verseStructure Structure
hi def link verseType Type
hi def link verseBoolean Boolean
hi def link verseOperatorWord Operator
hi def link verseOperator Operator
hi def link verseSpecifier PreProc
hi def link verseDecorator PreProc
hi def link verseNumber Number
hi def link verseFloat Float
hi def link verseCharacter Character
hi def link verseString String
hi def link verseEscape SpecialChar
hi def link verseInterpDelim Special
hi def link verseBlockComment Comment
hi def link verseLineComment Comment
hi def link versePath Include
hi def link verseFunction Function

let b:current_syntax = "verse"
