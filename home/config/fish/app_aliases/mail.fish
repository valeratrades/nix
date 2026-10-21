# himalaya mail shortcuts

function m --wraps himalaya; himalaya $argv; end

function mi --wraps 'himalaya envelope list -f INBOX'; himalaya envelope list -f INBOX $argv; end
function ma --wraps "himalaya envelope list -f '[Gmail]/All Mail'"; himalaya envelope list -f '[Gmail]/All Mail' $argv; end
function ms --wraps "himalaya envelope list -f '[Gmail]/Spam'"; himalaya envelope list -f '[Gmail]/Spam' $argv; end
function me --description "List sent mail with recipient info" --wraps "himalaya envelope list -f '[Gmail]/Sent Mail'"
	himalaya envelope list -f '[Gmail]/Sent Mail' -o json $argv \
		| jq -r '
			def to_utc:
				capture("^(?<dt>.*[0-9]{2}:[0-9]{2})(?<sign>[+-])(?<oh>[0-9]{2}):(?<om>[0-9]{2})$") |
				(.dt | gsub(" "; "T") | strptime("%Y-%m-%dT%H:%M") | mktime) as $epoch |
				((.oh|tonumber)*3600 + (.om|tonumber)*60) as $off |
				(if .sign == "-" then $epoch + $off else $epoch - $off end) |
				strftime("%Y-%m-%d %H:%M");
			.[] | [
				.id,
				([.flags[] | select(. == "Seen" | not)] | join(",")),
				.subject,
				.to.addr,
				(.date | to_utc)
			] | @tsv' \
		| awk -F'\t' '
			{ id[NR]=$1; fl[NR]=$2; su[NR]=$3; to[NR]=$4; dt[NR]=$5
			  if (length($1)>w1) w1=length($1)
			  if (length($2)>w2) w2=length($2)
			  if (length($3)>w3) w3=length($3)
			  if (length($4)>w4) w4=length($4)
			  n=NR }
			END {
			  g="\033[32m"; d="\033[38;5;242m"; h="\033[2;4;37m"; r="\033[0m"
			  printf h "%-*s  %-*s  %-*s  %-*s  %s" r "\n", w1,"ID", w2,"FLAGS", w3,"SUBJECT", w4,"TO", "DATE"
			  for (i=1;i<=n;i++)
			    printf g "%-*s" r "  " d "%-*s" r "  %-*s  " d "%-*s" r "  " d "%s" r "\n", w1,id[i], w2,fl[i], w3,su[i], w4,to[i], dt[i]
			}'
end
function md --wraps "himalaya envelope list -f '[Gmail]/Drafts'"; himalaya envelope list -f '[Gmail]/Drafts' $argv; end
function mt --wraps "himalaya envelope list -f '[Gmail]/Trash'"; himalaya envelope list -f '[Gmail]/Trash' $argv; end
function mu; himalaya envelope list -f INBOX -- 'not flag seen' $argv; end
function mr --wraps "himalaya message read -f '[Gmail]/All Mail'"; himalaya message read -f '[Gmail]/All Mail' $argv; end # mr <ID>; mr <ID1> <ID2>
function mR --wraps "himalaya message reply -f '[Gmail]/All Mail'"; himalaya message reply -f '[Gmail]/All Mail' $argv; end # mR <ID>; mR -A <ID> to reply-all
function mf --wraps 'himalaya folder list'; himalaya folder list $argv; end # overwrites some `METAFONT` thing I have, but no clue what it is, and don't care
function mw --description "Write a new email (Ctrl-C discards)" --wraps "himalaya message write"
	# himalaya catches SIGINT and loops instead of exiting.
	# We background it (keeping stdin via <&0) so bash can trap INT and SIGKILL it.
	# No job control = same process group, so both get SIGINT, but our kill -9 wins.
	bash -c '
		himalaya message write "$@" <&0 &
		PID=$!
		trap "kill -9 $PID 2>/dev/null; exit 130" INT
		wait $PID 2>/dev/null
	' -- $argv
end
