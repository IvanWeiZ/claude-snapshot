#!/bin/bash
# claude-snapshot remote installer
# Usage: curl -fsSL https://raw.githubusercontent.com/IvanWeiZ/claude-snapshot/main/install-remote.sh | bash
set -e

REPO_URL="https://github.com/IvanWeiZ/claude-snapshot.git"
INSTALL_DIR="${CLAUDE_SNAPSHOT_DIR:-$HOME/claude-snapshot}"

die() { echo "Error: $1" >&2; exit 1; }

echo "claude-snapshot installer"
echo ""

# Only check curl/git here; setup.sh checks the rest
command -v git >/dev/null || die "git is required but not installed"
[ -d "$HOME/.claude" ] || die "~/.claude/ not found. Install Claude Code first."

# Clone or update
if [ -d "$INSTALL_DIR/.git" ]; then
  echo "Existing repo found at $INSTALL_DIR, updating..."
  git -C "$INSTALL_DIR" pull --quiet 2>/dev/null || true
else
  echo "Cloning to $INSTALL_DIR..."
  git clone --depth=1 "$REPO_URL" "$INSTALL_DIR"
fi

# Run setup
echo ""
bash "$INSTALL_DIR/setup.sh"

echo ""
echo "To check status:  $INSTALL_DIR/setup.sh --status"
echo "To view history:  $INSTALL_DIR/setup.sh --log"
echo "To push to remote: connect a remote and set CLAUDE_SNAPSHOT_PUSH=1"
