function tgg; tg send -c general  $argv 2>/dev/null; end
function tgj; tg send -c journal  $argv 2>/dev/null; end
function tgn; tg send -c learning $argv 2>/dev/null; end
function tgm; tg send -c math     $argv 2>/dev/null; end
function tgp; tg send -c papers   $argv 2>/dev/null; end
function tgr; tg send -c trading  $argv 2>/dev/null; end
function tgi; tg send -c tooling  $argv 2>/dev/null; end
function tgv; tg send -c videos   $argv 2>/dev/null; end
function tgw; tg send -c work     $argv 2>/dev/null; end
function tgd; tg send -c discretionary_engine     $argv 2>/dev/null; end

function tgc --description 'send clipboard (image or text) to tg general'
	set -l img (wl-paste --list-types 2>/dev/null | string match -r '^image/(png|jpeg|webp)$')[1]
	if test -n "$img"
		# not deleted: the server's buffer worker reads it after `tg send` returns, /tmp is tmpfs
		set -l f /tmp/tgc-(date +%s%N).(string split -f2 / $img)
		wl-paste --type $img >$f
		tg send -c general -i -d $f $argv 2>/dev/null
	else
		wl-paste --no-newline | tg send -c general - 2>/dev/null
	end
end
