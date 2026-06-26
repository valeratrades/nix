# Blanks the always-on AskUserQuestion (clarifying-question interface) instructions that
# claude-code injects into the system prompt on every turn. They contradict my global
# CLAUDE.md ("do NOT ask me questions, just do the work"), and a model torn between the two
# writes worse code. The guidance is baked as literal UTF-8 strings into the bun-compiled
# ELF; we overwrite each occurrence with same-length whitespace so Bun's trailer offsets
# stay valid. The exact occurrence counts are asserted in the python script so the build
# fails loudly if upstream changes the wording.
{ pkgs, claude-code }:

claude-code.overrideAttrs (old: {
	postFixup = (old.postFixup or "") + ''
		${pkgs.python3}/bin/python3 ${./strip-claude-reminders.py} "$out/bin/.claude-unwrapped"
		${pkgs.python3}/bin/python3 ${./patch-claude-altexit.py} "$out/bin/.claude-unwrapped"
	'';
})
