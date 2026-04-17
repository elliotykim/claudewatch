#!/usr/bin/env bash
# Set up an additional Claude Code account for ClaudeWatch to track.
#
# Creates ~/.claude-<label>/ with symlinks back to ~/.claude for the things
# that can safely be shared (settings, plugins, history, etc.) and a copy of
# ~/.claude.json so your project list / MCP approvals carry over. Account-
# specific state (credentials, sessions, usage JSON) stays separate.
#
# Usage: ./setup-account.sh <label>
#   e.g. ./setup-account.sh personal  # creates ~/.claude-personal

set -euo pipefail

if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo "Usage: $0 <label>" >&2
  echo "  e.g. $0 personal   # creates ~/.claude-personal + claude-personal alias" >&2
  exit 1
fi

label="$1"
if [[ ! "$label" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: label must be alphanumeric / dash / underscore (got: '$label')" >&2
  exit 1
fi

src="$HOME/.claude"
dst="$HOME/.claude-$label"
alias_line="alias claude-$label=\"CLAUDE_CONFIG_DIR=$dst claude\""

if [ ! -d "$src" ]; then
  echo "Error: $src does not exist. Run Claude Code at least once first." >&2
  exit 1
fi

# Symlinked items: config + hook scripts, code/assets, working-dir-keyed
# artifacts (projects, todos, history). Sharing these means /resume works
# across accounts in the same repo and you don't reinstall plugins twice.
shared=(
  settings.json
  statusline.sh
  statusline-command.sh
  plugins
  skills
  projects
  todos
  plans
  tasks
  file-history
  shell-snapshots
  history.jsonl
  paste-cache
  image-cache
  backups
)

echo "Setting up Claude account '$label' at $dst"

mkdir -p "$dst"

for item in "${shared[@]}"; do
  if [ -e "$src/$item" ] && [ ! -e "$dst/$item" ]; then
    ln -s "$src/$item" "$dst/$item"
    echo "  linked: $item"
  elif [ -e "$dst/$item" ]; then
    echo "  skipped (exists): $item"
  fi
done

# .claude.json gets mutated by Claude Code, so copy rather than symlink.
# This way both accounts start with the same project list / MCP approvals
# but diverge from here.
if [ -f "$src/.claude.json" ] && [ ! -e "$dst/.claude.json" ]; then
  cp "$src/.claude.json" "$dst/.claude.json"
  echo "  copied:  .claude.json"
elif [ -e "$dst/.claude.json" ]; then
  echo "  skipped (exists): .claude.json"
fi

cat <<EOF

Done. Next steps:

  1. Add this alias to your shell config (~/.zshrc or ~/.bashrc):

       $alias_line

     Then: source ~/.zshrc  (or open a new terminal)

  2. Log in with the new account:

       claude-$label

     Send any prompt so the statusline hook writes $dst/claudewatch-usage.json.

  3. In ClaudeWatch: gear icon -> Claude accounts -> Add account -> pick $dst.

EOF
