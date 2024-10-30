#NB: the fucking morons designing this language decided that an array starts at 1. (It's still from 0 in bash)

# Global settings
MNML_OK_COLOR="${MNML_OK_COLOR:-2}"
MNML_ERR_COLOR="${MNML_ERR_COLOR:-1}"

MNML_USER_CHAR="${MNML_USER_CHAR:-λ}"
MNML_INSERT_CHAR="${MNML_INSERT_CHAR:-›}"
MNML_NORMAL_CHAR="${MNML_NORMAL_CHAR:-·}"
MNML_ELLIPSIS_CHAR="${MNML_ELLIPSIS_CHAR:-..}"
MNML_BGJOB_MODE=${MNML_BGJOB_MODE:-4}

[ "${+MNML_PROMPT}" -eq 0 ] && MNML_PROMPT=(mnml_ssh mnml_status mnml_keymap)
[ "${+MNML_RPROMPT}" -eq 0 ] && MNML_RPROMPT=('mnml_cwd 2 0' mnml_git mnml_files)
[ "${+MNML_INFOLN}" -eq 0 ] && MNML_INFOLN=(mnml_err mnml_jobs mnml_uhp mnml_files)

#NB: subset dirs have to be earlier, as I would break on them in `mnml_cmd` otherwise. (eg: `s/valera` has to be before `s`)
local special_dirs=("s/help_scripts" "s/valera" "tmp" "Downloads" "s/ai-news-trade-bot" "s/l" "g" ".config" "s" "Documents/Books" "Documents/Papers" "math")
local special_chars=("h" "v" "t" "d" "a" "l" "g" "c" "s" "b" "p" "m")

function custom_cwd {
	#NB: "%~" returns a name with non-standard ~ character. The following special_dir spec contains it as well.
	local cwd="%~"
	cwd="${(%)cwd}"
	for i in {1..${#special_dirs[@]}}; do
		local tilda_plus_dir="~/${special_dirs[$i]}"
		if [[ "$cwd" == "$tilda_plus_dir"* ]]; then
			cwd="${cwd/#$tilda_plus_dir/$special_chars[$i]}"
			break
		fi
	done
	echo $cwd
}


# Components
function mnml_status {
	local okc="$MNML_OK_COLOR"
	local errc="$MNML_ERR_COLOR"
	local uchar="$MNML_USER_CHAR"

	if [ "$PWD" = "$HOME" ]; then
		uchar="~"
	elif [ "$PWD" = "/" ]; then
		uchar="/"
	fi
	for i in {1..${#special_dirs[@]}}; do
		local home_plus_dir="${HOME}/${special_dirs[$i]}"
		if [ "$PWD" = "$home_plus_dir" ]; then
			uchar="${special_chars[$i]}"
			break
		fi
	done

	local job_ansi="0"
	if [ -n "$(jobs | sed -n '$=')" ]; then
		job_ansi="$MNML_BGJOB_MODE"
	fi

		# 4 is blue. Default was green.
		local err_ansi="4"
		if [ "$MNML_LAST_ERR" != "0" ]; then
			err_ansi="$MNML_ERR_COLOR"
		fi

		printf '%b' "%{\e[$job_ansi;3${err_ansi}m%}%(!.#.$uchar)%{\e[0m%}"
	}

	function mnml_keymap {
		local kmstat="$MNML_INSERT_CHAR"
		[ "$KEYMAP" = 'vicmd' ] && kmstat="$MNML_NORMAL_CHAR"
		printf '%b' "$kmstat"
	}

	function mnml_cwd {
		local echar="$MNML_ELLIPSIS_CHAR"
		local seg_len="${2:-0}"

		local _w="%{\e[0m%}"
		local _g="%{\e[38;5;244m%}"

		if [ "$seg_len" -gt 0 ] && [ "$seg_len" -lt 4 ]; then
			seg_len=4
		fi
		local seg_hlen=$((seg_len / 2 - 1))

		local cwd=$(custom_cwd)
		cwd=("${(@s:/:)cwd}")

		local pi=""
		for i in {1..${#cwd}}; do
			pi="$cwd[$i]"
			if [ "$seg_len" -gt 0 ] && [ "${#pi}" -gt "$seg_len" ]; then
				cwd[$i]="${pi:0:$seg_hlen}$_w$echar$_g${pi: -$seg_hlen}"
			fi
		done

		printf '%b' "$_g${(j:/:)cwd//\//$_w/$_g}$_w"
	}

	function mnml_git {
		local statc="%{\e[0;3${MNML_OK_COLOR}m%}" # assume clean
		local bname="$(git rev-parse --abbrev-ref HEAD 2> /dev/null)"

		if [ -n "$bname" ]; then
			if [ -n "$(git status --porcelain 2> /dev/null)" ]; then
				statc="%{\e[0;3${MNML_ERR_COLOR}m%}"
			fi
			printf '%b' "$statc$bname%{\e[0m%}"
		fi
	}

	function mnml_uhp {
		local _w="%{\e[0m%}"
		local _g="%{\e[38;5;244m%}"
		#local cwd="%~"
		#cwd="${(%)cwd}"
		local cwd=$(custom_cwd)

		printf '%b' "$_g%n$_w@$_g%m$_w:$_g${cwd//\//$_w/$_g}$_w"
	}

	function mnml_ssh {
		if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
			printf '%b' "$(hostname -s)"
		fi
	}

	function mnml_err {
		local _w="%{\e[0m%}"
		local _err="%{\e[3${MNML_ERR_COLOR}m%}"

		if [ "${MNML_LAST_ERR:-0}" != "0" ]; then
			printf '%b' "$_err$MNML_LAST_ERR$_w"
		fi
	}

	function mnml_jobs {
		local _w="%{\e[0m%}"
		local _g="%{\e[38;5;244m%}"

		local job_n="$(jobs | sed -n '$=')"
		if [ "$job_n" -gt 0 ]; then
			printf '%b' "$_g$job_n$_w&"
		fi
	}

	function mnml_files {
		local _ls="$(env which ls)"
		local _w="%{\e[0m%}" # resets to default color
		local _g="%{\e[38;5;244m%}" # comment color

		local a_files="$($_ls -1A | sed -n '$=')"
		local v_files="$($_ls -1 | sed -n '$=')"
		local h_files="$((a_files - v_files))"
		#local _size="$(ls -lAh . | awk 'NR == 1 {n=split($0, words, " "); print words[n]; exit}')"
		
		local output="${_w}[$_g${v_files:-0}"
		if [ "${h_files:-0}" -gt 0 ]; then
			output="${output} $_w($_g$h_files$_w)"
		fi
		#output="${output} $_g${_size}"
	
		output="${output}${_w}]"

		printf '%b' "$output"
	}

# Wrappers & utils
# join outpus of components
function _mnml_wrap {
	local -a arr
	arr=()
	local cmd_out=""
	local cmd
	for cmd in ${(P)1}; do
		cmd_out="$(eval "$cmd")"
		if [ -n "$cmd_out" ]; then
			arr+="$cmd_out"
		fi
	done

	printf '%b' "${(j: :)arr}"
}

# expand string as prompt would do
function _mnml_iline {
	echo "${(%)1}"
}

# capture exit status and reset prompt
function _mnml_zle-line-init {
MNML_LAST_ERR="$?" # I need to capture this ASAP
zle reset-prompt
}

# redraw prompt on keymap select
function _mnml_zle-keymap-select {
zle reset-prompt
}

# properly bind widgets
# see: https://github.com/zsh-users/zsh-syntax-highlighting/blob/1f1e629290773bd6f9673f364303219d6da11129/zsh-syntax-highlighting.zsh#L292-L356
function _mnml_bind_widgets() {
	zmodload zsh/zleparameter

	local -a to_bind
	to_bind=(zle-line-init zle-keymap-select buffer-empty)

	typeset -F SECONDS
	local zle_wprefix=s$SECONDS-r$RANDOM

	local cur_widget
	for cur_widget in $to_bind; do
		case "${widgets[$cur_widget]:-""}" in
			user:_mnml_*);;
			user:*)
				zle -N $zle_wprefix-$cur_widget ${widgets[$cur_widget]#*:}
				eval "_mnml_ww_${(q)zle_wprefix}-${(q)cur_widget}() { _mnml_${(q)cur_widget}; zle ${(q)zle_wprefix}-${(q)cur_widget} }"
				zle -N $cur_widget _mnml_ww_$zle_wprefix-$cur_widget
				;;
			*)
				zle -N $cur_widget _mnml_$cur_widget
				;;
		esac
	done
}

# # Setup
autoload -U colors && colors
setopt prompt_subst

PROMPT='$(_mnml_wrap MNML_PROMPT) '
RPROMPT='$(_mnml_wrap MNML_RPROMPT)'

_mnml_bind_widgets
#
