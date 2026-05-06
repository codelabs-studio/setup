#!/bin/bash
# sync-skills-cache.sh
# PostToolUse hook: auto-syncs SKILL.md edits to ALL known copies.
#
# There are 3 locations where a skill can live — all must be in sync:
#   1. Dev-servers source:      ~/.claude/plugins/dev-servers/skills/{dir}/SKILL.md
#   2. Codelabs-toolkit source: ~/.claude/plugins/codelabs-toolkit/skills/{name}/SKILL.md
#   3. Codelabs-toolkit cache:  ~/.claude/plugins/cache/local/codelabs-toolkit/1.0.0/skills/{name}/SKILL.md
#
# The ~/.claude/skills/{name}/ symlinks point to location 1.
# Claude Code reads from 2 (autoDiscovery) and/or 3 (installed cache).
# This hook ensures all three stay in sync after any Write or Edit.

TOOLKIT_SOURCE="/Users/josediaz/.claude/plugins/codelabs-toolkit/skills"
TOOLKIT_CACHE="/Users/josediaz/.claude/plugins/cache/local/codelabs-toolkit/1.0.0/skills"

# Read JSON from stdin (provided by Claude Code)
INPUT=$(cat)

# Extract file_path from tool input
FILE_PATH=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('tool_input', {}).get('file_path', ''))
except:
    print('')
" <<< "$INPUT" 2>/dev/null)

# Only process SKILL.md files
[[ -z "$FILE_PATH" ]] || [[ "$FILE_PATH" != *"SKILL.md" ]] && exit 0

# Resolve symlinks to real path
REAL_PATH=$(realpath "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")

# Only process files inside a skills/ directory
[[ "$REAL_PATH" != *"/skills/"*"/SKILL.md" ]] && exit 0

# File must exist and be readable
[[ ! -f "$REAL_PATH" ]] && exit 0

# Read skill name from YAML frontmatter (name: field)
SKILL_NAME=$(grep "^name:" "$REAL_PATH" 2>/dev/null | head -1 | sed 's/^name:[[:space:]]*//' | tr -d '[:space:]')

[[ -z "$SKILL_NAME" ]] && exit 0

# Sync to codelabs-toolkit SOURCE (what autoDiscovery reads)
TOOLKIT_SOURCE_FILE="$TOOLKIT_SOURCE/$SKILL_NAME/SKILL.md"
if [[ -d "$TOOLKIT_SOURCE/$SKILL_NAME" ]]; then
    cp "$REAL_PATH" "$TOOLKIT_SOURCE_FILE"
elif [[ -d "$TOOLKIT_SOURCE" ]]; then
    mkdir -p "$TOOLKIT_SOURCE/$SKILL_NAME"
    cp "$REAL_PATH" "$TOOLKIT_SOURCE_FILE"
fi

# Sync to codelabs-toolkit CACHE (what installed plugin reads)
TOOLKIT_CACHE_FILE="$TOOLKIT_CACHE/$SKILL_NAME/SKILL.md"
if [[ -d "$TOOLKIT_CACHE/$SKILL_NAME" ]]; then
    cp "$REAL_PATH" "$TOOLKIT_CACHE_FILE"
elif [[ -d "$TOOLKIT_CACHE" ]]; then
    mkdir -p "$TOOLKIT_CACHE/$SKILL_NAME"
    cp "$REAL_PATH" "$TOOLKIT_CACHE_FILE"
fi

# Ensure ~/.claude/skills/{name} symlink exists (required for Claude Code discovery)
SKILLS_SYMLINK_DIR="/Users/josediaz/.claude/skills"
SKILLS_SYMLINK="$SKILLS_SYMLINK_DIR/$SKILL_NAME"
if [[ ! -L "$SKILLS_SYMLINK" ]] && [[ -d "$TOOLKIT_SOURCE/$SKILL_NAME" ]]; then
    ln -s "$TOOLKIT_SOURCE/$SKILL_NAME" "$SKILLS_SYMLINK"
fi

echo "✓ Skill '$SKILL_NAME' synced to all locations"
