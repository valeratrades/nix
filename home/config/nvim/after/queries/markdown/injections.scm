;; extends

; scripters strips `<div k="v">`/`</div>` lines as scope markers, so what follows them is markdown, not the HTML block CommonMark sees
((html_block) @injection.content
  (#lua-match? @injection.content "^ ? ? ?</?div[^\n]*>%s*\n")
  (#scr-md? @injection.content)
  (#offset! @injection.content 1 0 0 0)
  (#set! injection.language "markdown"))
