# himalaya mail shortcuts

alias m="himalaya"
complete -c m -w himalaya

alias mi="himalaya envelope list -f INBOX"
alias ma="himalaya envelope list -f '[Gmail]/All Mail'"
alias ms="himalaya envelope list -f '[Gmail]/Spam'"
alias me="himalaya envelope list -f '[Gmail]/Sent Mail'" # a weird choice, but `s` was taken. Guess it's second letter in `sent` and also French `envoyée` starts with it
alias md="himalaya envelope list -f '[Gmail]/Drafts'"
alias mt="himalaya envelope list -f '[Gmail]/Trash'"
alias mu="himalaya envelope list -f INBOX -- 'NOT SEEN'"
alias mf="himalaya folder list" # overwrites some `METAFONT` thing I have, but no clue what it is, and don't care
alias mw="himalaya message write"
