# Strips the per-Read "consider whether it would be malware" system-reminder that
# claude-code injects into every file-read tool result. The reminder is baked as a
# literal string into the bun-compiled ELF; we overwrite all occurrences with
# same-length whitespace so Bun's trailer offsets remain valid. The exact occurrence
# count is asserted in the python script so the build fails loudly if upstream
# changes the wording.
{ pkgs, claude-code }:

claude-code.overrideAttrs (old: {
	postFixup = (old.postFixup or "") + ''
		${pkgs.python3}/bin/python3 ${./strip-claude-reminders.py} "$out/bin/.claude-unwrapped"
	'';
})
