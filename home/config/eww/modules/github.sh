#!/usr/bin/env sh

notifications=$(timeout 10 gh api notifications 2>/dev/null | jq '. | length')
[ -z "$notifications" ] && echo "" || echo "$notifications" 
