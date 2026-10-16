printf '\033[1;97;45m TEAM \033[0m '; c=$(jq -r '.statusLine.command // empty' "$HOME/.claude/settings.json" 2>/dev/null); if [ -n "$c" ]; then eval "$c"; else echo; fi; : claude-team-statusline-v1
