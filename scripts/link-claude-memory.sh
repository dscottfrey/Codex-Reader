#!/usr/bin/env bash
#
# link-claude-memory.sh
#
# WHAT THIS DOES:
#   Symlinks this machine's Claude Code per-project memory directory
#   to the copy of memory files kept in this repo (`.claude/memory/`).
#   Run once per machine after cloning the repo.
#
# WHY:
#   Claude Code stores per-project memory at
#     ~/.claude/projects/<encoded-project-path>/memory/
#   By default that directory is machine-local, so facts the assistant
#   learns on the desktop don't reach the laptop and vice versa. Codex
#   is directed by a single owner across two machines — memory should
#   be a single source of truth, shared via git like every other piece
#   of project context.
#
# HOW THE ENCODING WORKS:
#   Claude Code takes the absolute path to the project root and
#   replaces every `/` with `-`. Spaces are kept as-is. So
#     /Users/scott/Documents/Code/Codex Reader
#   becomes
#     -Users-scott-Documents-Code-Codex-Reader
#   which is the folder name under ~/.claude/projects/.
#
# SAFETY:
#   If a non-symlink memory directory already exists on this machine,
#   we move it to a .bak suffix so nothing is lost. If a symlink is
#   already in place (you're re-running the script), we replace it.
#

set -euo pipefail

# Resolve the repo root relative to this script's location.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_MEMORY="$REPO_ROOT/.claude/memory"

if [ ! -d "$REPO_MEMORY" ]; then
  echo "Error: $REPO_MEMORY does not exist." >&2
  echo "Run this script from a clone of the codex-reader repository." >&2
  exit 1
fi

# Replace every `/` with `-` to match Claude Code's encoding.
PROJECT_KEY="$(echo "$REPO_ROOT" | sed 's|/|-|g')"
CLAUDE_PROJECT_DIR="$HOME/.claude/projects/$PROJECT_KEY"
CLAUDE_MEMORY="$CLAUDE_PROJECT_DIR/memory"

mkdir -p "$CLAUDE_PROJECT_DIR"

# If a real directory is already there, back it up — don't overwrite
# anything the user might care about without their consent.
if [ -d "$CLAUDE_MEMORY" ] && [ ! -L "$CLAUDE_MEMORY" ]; then
  BACKUP="${CLAUDE_MEMORY}.bak.$(date +%Y%m%d-%H%M%S)"
  echo "Backing up existing memory directory:"
  echo "  $CLAUDE_MEMORY"
  echo "-> $BACKUP"
  mv "$CLAUDE_MEMORY" "$BACKUP"
fi

# If a symlink is there (re-running this script), replace it.
if [ -L "$CLAUDE_MEMORY" ]; then
  rm "$CLAUDE_MEMORY"
fi

ln -s "$REPO_MEMORY" "$CLAUDE_MEMORY"

echo "Memory symlinked:"
echo "  $CLAUDE_MEMORY"
echo "-> $REPO_MEMORY"
echo
echo "This machine's Claude Code now reads and writes project memory"
echo "from the repo. Commit changes to share them with the other machine."
