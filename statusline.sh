#!/bin/bash

# Add the following to ~/.claude/settings.json to enable this status line:
#
#   "statusLine": {
#     "type": "command",
#     "command": "~/.claude/statusline.sh"
#   }

# Read JSON data from stdin (sent by Claude Code)
input=$(cat)

# Model
MODEL_ID=$(echo "$input" | jq -r '.model.id // "unknown"')
MODEL_NAME=$(echo "$input" | jq -r '.model.display_name // "unknown"')

# Workspace
DIR=$(echo "$input" | jq -r '.workspace.current_dir // ""')
DIR=$(echo "$DIR" | sed "s|^$HOME|~|")

# Cost
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
COST_FMT=$(printf '$%.4f' "$COST")
API_DURATION_MS=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
API_SEC=$((API_DURATION_MS / 1000))
API_MINS=$((API_SEC / 60))
API_SECS=$((API_SEC % 60))

# Wall time - track session start time in a file keyed by session ID
SESSION_ID=$(echo "$input" | jq -r '.session_id // "unknown"')
WALL_TIME_DIR="/tmp/statusline-wall-time"
mkdir -p "$WALL_TIME_DIR"
WALL_TIME_FILE="${WALL_TIME_DIR}/${SESSION_ID}"
if [ ! -f "$WALL_TIME_FILE" ]; then
    date +%s > "$WALL_TIME_FILE"
fi
SESSION_START=$(cat "$WALL_TIME_FILE")
WALL_SEC=$(($(date +%s) - SESSION_START))
WALL_MINS=$((WALL_SEC / 60))
WALL_SECS=$((WALL_SEC % 60))

# Context window - use used_percentage to derive actual current context used
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0')

# Derive current context used from pre-calculated percentage (accurate, not cumulative)
USED=$(awk "BEGIN {printf \"%.0f\", $PCT * $CONTEXT_SIZE / 100}")

# Format as X.Xk
USED_K=$(awk "BEGIN {printf \"%.1f\", $USED / 1000}")
CTX_K=$(awk "BEGIN {printf \"%.1f\", $CONTEXT_SIZE / 1000}")
PCT_FMT=$(awk "BEGIN {printf \"%.1f\", $PCT}")

# Session (already extracted above for wall time tracking)

# Cache git branch + remote (runs frequently, git can be slow in large repos)
CACHE_FILE="/tmp/statusline-git-cache"
CACHE_MAX_AGE=5

cache_is_stale() {
    [ ! -f "$CACHE_FILE" ] || \
    [ $(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0))) -gt $CACHE_MAX_AGE ]
}

if cache_is_stale; then
    BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
    REMOTE=$(git remote get-url origin 2>/dev/null | sed 's/git@github.com:/https:\/\/github.com\//' | sed 's/\.git$//' || echo "")
    STAGED=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED=$(git diff --diff-filter=M --name-only 2>/dev/null | wc -l | tr -d ' ')
    DELETED=$(git diff --diff-filter=D --name-only 2>/dev/null | wc -l | tr -d ' ')
    RENAMED=$(git diff --cached --diff-filter=R --name-only 2>/dev/null | wc -l | tr -d ' ')
    UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
    CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l | tr -d ' ')
    STASHED=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
    # ahead/behind remote tracking branch
    AHEAD=0; BEHIND=0
    AB=$(git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
    if [ -n "$AB" ]; then
        AHEAD=$(echo "$AB" | awk '{print $1}')
        BEHIND=$(echo "$AB" | awk '{print $2}')
    fi
    echo "${BRANCH}|${REMOTE}|${STAGED}|${MODIFIED}|${DELETED}|${RENAMED}|${UNTRACKED}|${CONFLICTS}|${STASHED}|${AHEAD}|${BEHIND}" > "$CACHE_FILE"
fi

IFS='|' read -r BRANCH REMOTE STAGED MODIFIED DELETED RENAMED UNTRACKED CONFLICTS STASHED AHEAD BEHIND < "$CACHE_FILE"
GIT_PART=""
if [ -n "$BRANCH" ]; then
    # ANSI colors
    YELLOW='\033[33m'
    RESET='\033[0m'

    # oh-my-zsh style symbols — yellow for dirty working tree, default for informational
    GIT_STATUS=""
    [ "$STAGED" -gt 0 ] 2>/dev/null && GIT_STATUS="${GIT_STATUS} ${YELLOW}✚${STAGED}${RESET}"
    [ "$MODIFIED" -gt 0 ] 2>/dev/null && GIT_STATUS="${GIT_STATUS} ${YELLOW}✱${MODIFIED}${RESET}"
    [ "$DELETED" -gt 0 ] 2>/dev/null && GIT_STATUS="${GIT_STATUS} ${YELLOW}✖${DELETED}${RESET}"
    [ "$RENAMED" -gt 0 ] 2>/dev/null && GIT_STATUS="${GIT_STATUS} ${YELLOW}➜${RENAMED}${RESET}"
    [ "$UNTRACKED" -gt 0 ] 2>/dev/null && GIT_STATUS="${GIT_STATUS} ${YELLOW}◼${UNTRACKED}${RESET}"
    [ "$CONFLICTS" -gt 0 ] 2>/dev/null && GIT_STATUS="${GIT_STATUS} ${YELLOW}═${CONFLICTS}${RESET}"
    [ "$STASHED" -gt 0 ] 2>/dev/null && GIT_STATUS="${GIT_STATUS} ⚡${STASHED}"
    [ "$AHEAD" -gt 0 ] 2>/dev/null && GIT_STATUS="${GIT_STATUS} ⬆${AHEAD}"
    [ "$BEHIND" -gt 0 ] 2>/dev/null && GIT_STATUS="${GIT_STATUS} ⬇${BEHIND}"

    if [ -n "$REMOTE" ]; then
        # Get org/repo from URL (last two path segments)
        ORG_REPO=$(echo "$REMOTE" | sed 's|.*/\([^/]*/[^/]*\)$|\1|')
        # OSC 8 clickable link: \e]8;;URL\a TEXT \e]8;;\a
        GIT_PART="🔗 $(printf '%b' "\e]8;;${REMOTE}\a${ORG_REPO}\e]8;;\a")   🌿 ${BRANCH}${GIT_STATUS}"
    else
        GIT_PART="🌿 ${BRANCH}${GIT_STATUS}"
    fi
fi

# Line 1: path, repo link, branch
if [ -n "$GIT_PART" ]; then
    printf '%b\n' "📁 ${DIR}   ${GIT_PART}"
else
    echo "📁 ${DIR}"
fi
# Line 2: context, model, cost, api time, wall time, session
echo "🧠 ${USED_K}k / ${CTX_K}k (${PCT_FMT}%)   🤖 ${MODEL_ID}   💰 ${COST_FMT}   ⏱️ ${API_MINS}m ${API_SECS}s   🕐 ${WALL_MINS}m ${WALL_SECS}s   📋 ${SESSION_ID}"

