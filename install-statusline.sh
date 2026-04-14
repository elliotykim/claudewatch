#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
STATUSLINE_SRC="$SCRIPT_DIR/statusline.sh"
STATUSLINE_DST="$CLAUDE_DIR/statusline.sh"

# Check that the source script exists
if [ ! -f "$STATUSLINE_SRC" ]; then
    echo "Error: statusline.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Check jq is available (needed by the statusline script at runtime)
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required but not installed."
    echo "  brew install jq"
    exit 1
fi

# Ensure ~/.claude exists
mkdir -p "$CLAUDE_DIR"

# Copy statusline script
cp "$STATUSLINE_SRC" "$STATUSLINE_DST"
chmod +x "$STATUSLINE_DST"
echo "Installed statusline.sh -> $STATUSLINE_DST"

# Configure settings.json
if [ -f "$SETTINGS_FILE" ]; then
    # Check if statusLine is already configured
    existing=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)
    if [ "$existing" = "~/.claude/statusline.sh" ]; then
        echo "settings.json already configured — nothing to change."
    else
        # Merge statusLine into existing settings
        tmp=$(mktemp)
        jq '. + {"statusLine": {"type": "command", "command": "~/.claude/statusline.sh"}}' "$SETTINGS_FILE" > "$tmp"
        mv "$tmp" "$SETTINGS_FILE"
        echo "Updated $SETTINGS_FILE with statusLine config."
    fi
else
    # Create a minimal settings.json
    cat > "$SETTINGS_FILE" <<'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
EOF
    echo "Created $SETTINGS_FILE with statusLine config."
fi

echo "Done. Restart Claude Code to see the status line."
