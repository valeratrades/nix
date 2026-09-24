#!/usr/bin/env bash
# PermissionRequest: approve everything except prompts that are the actual interaction with the user
case "$(jq -r .tool_name)" in
  AskUserQuestion|ExitPlanMode|EnterPlanMode) exit 0 ;;
esac
echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
