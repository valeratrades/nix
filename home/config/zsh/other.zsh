#NB: the fucking morons designing this language decided that an array starts at 1. (It's still from 0 in bash)


setopt INTERACTIVE_COMMENTS
bindkey -d # disable default keybinds
# allow backspace past insert start
bindkey "^?" backward-delete-char

# make : act like opening commandline mode
commandline-mode() {
    zle kill-buffer
    zle vi-insert
}
zle -N commandline-mode
bindkey -M vicmd ":" commandline-mode

# the '-' is supposed to mimic '_' in vim
# however it is bugged for the first column
function line-text-object {
  MARK=0
  CURSOR=$#BUFFER
  REGION_ACTIVE=1
}
zle -N line-text-object
bindkey -M viopp "l" line-text-object

autoload -U select-quoted
zle -N select-quoted
for m in visual viopp; do
    for c in {a,i}{\',\",\`}; do
        bindkey -M $m $c select-quoted
    done
done

autoload -U select-bracketed
zle -N select-bracketed
for m in visual viopp; do
    for c in {a,i}${(s..)^:-'()[]{}<>bB'}; do
        bindkey -M $m $c select-bracketed
    done
done

# # Autocompletion
source "$HOME/.config/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
#source "$HOME/.config/zsh/plugins/fzf-tab/fzf-tab.plugin.zsh"

setopt nocaseglob
setopt no_list_ambiguous
setopt complete_in_word

fpath+="$HOME/.config/zsh/completions"
autoload -Uz compinit && compinit -u
zstyle ':completion:*' matcher-list '' 'm:{[:lower:]}={[:upper:]}' 'm:{[:lower:]}={[:upper:]} r:|?=**'

complete-word() {
  _main_complete
  compstate[list]='list'
  local word=$PREFIX$SUFFIX
  (( compstate[unambiguous_cursor] <= ${#word} )) && compstate[insert]='menu'
}
# ^I is the tab key
bindkey '^I' complete-word
#

# # syntax highlighting
#source "$HOME/.config/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
#if [ -n "$ZSH_HIGHLIGHT_VERSION" ]; then
#    ZSH_HIGHLIGHT_STYLES[comment]='fg=red'
#    ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=green'
#    ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=green'
#    ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument-unclosed]='fg=green'
#    ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=green'
#    ZSH_HIGHLIGHT_STYLES[double-quoted-argument-unclosed]='fg=green'
#    ZSH_HIGHLIGHT_STYLES[command]='none'
#    ZSH_HIGHLIGHT_STYLES[builtin]='none'
#    ZSH_HIGHLIGHT_STYLES[precommand]='fg=yellow'
#    ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=magenta'
#    ZSH_HIGHLIGHT_STYLES[redirection]='fg=cyan,bold'
#    ZSH_HIGHLIGHT_STYLES[arg0]='none'
#    ZSH_HIGHLIGHT_STYLES[path]='none'
#    ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=red'
#    ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=magenta'
#fi
#

# # accept-line hooks
accept-math-line() {
    # execute the expression using python
    echo
    python3 -c "print(${BUFFER})"
    # save history and accept an empty line make it usable
    print -s "$BUFFER"
    BUFFER=""
    zle .accept-line
}
accept-line () {
if [[ "$BUFFER" =~ "^[0-9].*" ]]; then
	# if the commandline is a mathematical expression, evaluate it
	accept-math-line
elif [[ "$BUFFER" = "" ]]; then
	# if it is empty, redisplay the prompt two lines down. this is much
	# faster than accepting an empty line since it avoids all the
	# processing zsh has to do after a command has executed
	printf "\n\n"
else
	# otherwise, accept the line normally
	zle .accept-line
fi
}
zle -N accept-line accept-line
#

eval "$(zoxide init zsh)" # to get completions
