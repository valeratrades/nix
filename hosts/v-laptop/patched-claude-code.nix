# Blanks the always-on AskUserQuestion (clarifying-question interface) instructions that
# claude-code injects into the system prompt on every turn. They contradict my global
# CLAUDE.md ("do NOT ask me questions, just do the work"), and a model torn between the two
# writes worse code. The guidance is baked as literal UTF-8 strings into the bun-compiled
# ELF; we overwrite each occurrence with same-length whitespace so Bun's trailer offsets
# stay valid. The exact occurrence counts are asserted in the python script so the build
# fails loudly if upstream changes the wording.
{ pkgs, claude-code }:

claude-code.overrideAttrs (old: {
	nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
	postFixup = (old.postFixup or "") + ''
		cp "$out/bin/.claude-unwrapped" "$TMPDIR/claude-unpatched"
		${pkgs.python3}/bin/python3 ${./strip-claude-reminders.py} "$out/bin/.claude-unwrapped"
		${pkgs.python3}/bin/python3 ${./patch-claude-altexit.py} "$out/bin/.claude-unwrapped"
		${pkgs.python3}/bin/python3 ${./patch-claude-queuejoin.py} "$out/bin/.claude-unwrapped"
		${pkgs.python3}/bin/python3 ${./patch-claude-1m.py} "$out/bin/.claude-unwrapped"
		${pkgs.python3}/bin/python3 ${./patch-claude-noconfirm.py} "$out/bin/.claude-unwrapped"
		${pkgs.python3}/bin/python3 ${./detach-claude-bytecode.py} "$TMPDIR/claude-unpatched" "$out/bin/.claude-unwrapped"
		# every workspace trusted, nested repos included (they stopped inheriting trust from `/`)
		wrapProgram "$out/bin/claude" --set CLAUDE_CODE_SANDBOXED 1
	'';
})
