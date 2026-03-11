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
# --- Terminal-width-aware truncation ---
# Get terminal width (fall back to 120 if unavailable)
TERM_WIDTH=$(tput cols 2>/dev/null || echo 120)

# Helper: truncate a string to max length, adding "…" if truncated
# Usage: truncate "string" max_len
truncate() {
    local str="$1" max="$2"
    if [ "${#str}" -gt "$max" ]; then
        echo "${str:0:$((max - 1))}…"
    else
        echo "$str"
    fi
}

# Helper: compute visible length of a string (strip ANSI escape sequences and OSC 8 hyperlinks)
# ANSI escapes and OSC 8 sequences take zero columns on screen
visible_len() {
    # Strip OSC 8 hyperlink sequences: \e]8;;...\a  (both opening and closing)
    # Strip ANSI color codes: \e[...m
    local stripped
    stripped=$(printf '%b' "$1" | sed $'s/\033]8;;[^\a]*\a//g' | sed $'s/\033\\[[0-9;]*m//g')
    echo "${#stripped}"
}

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

    # Compute visible width of git status symbols (strip ANSI)
    GIT_STATUS_LEN=$(visible_len "$GIT_STATUS")

    if [ -n "$REMOTE" ]; then
        # Get org/repo from URL (last two path segments)
        ORG_REPO=$(echo "$REMOTE" | sed 's|.*/\([^/]*/[^/]*\)$|\1|')

        # Calculate fixed overhead for line 1:
        # "📁 " (3) + "   " (3) + "🔗 " (3) + "   " (3) + "🌿 " (3) = 15 chars of chrome
        # Emoji chars may be 2-wide in some terminals, so use a conservative estimate
        CHROME_WIDTH=19
        GIT_STATUS_WIDTH=$GIT_STATUS_LEN

        # Budget available for variable-length content (dir + org/repo + branch)
        BUDGET=$((TERM_WIDTH - CHROME_WIDTH - GIT_STATUS_WIDTH))

        # Allocate budget proportionally: dir gets 35%, org/repo gets 30%, branch gets 35%
        # But first ensure minimums of 10 chars each
        if [ "$BUDGET" -lt 30 ]; then
            # Extremely narrow terminal — just hard-truncate everything
            DIR_MAX=10; REPO_MAX=10; BRANCH_MAX=10
        else
            DIR_MAX=$((BUDGET * 35 / 100))
            REPO_MAX=$((BUDGET * 30 / 100))
            BRANCH_MAX=$((BUDGET * 35 / 100))
            # Ensure minimums
            [ "$DIR_MAX" -lt 10 ] && DIR_MAX=10
            [ "$REPO_MAX" -lt 10 ] && REPO_MAX=10
            [ "$BRANCH_MAX" -lt 10 ] && BRANCH_MAX=10
        fi

        # Smart reallocation: if one segment is short, give its surplus to others
        DIR_ACTUAL=${#DIR}
        REPO_ACTUAL=${#ORG_REPO}
        BRANCH_ACTUAL=${#BRANCH}

        # Pass 1: collect surplus from segments that don't need their full allocation
        SURPLUS=0
        DEFICIT_COUNT=0
        if [ "$DIR_ACTUAL" -lt "$DIR_MAX" ]; then
            SURPLUS=$((SURPLUS + DIR_MAX - DIR_ACTUAL))
            DIR_MAX=$DIR_ACTUAL
        else
            DEFICIT_COUNT=$((DEFICIT_COUNT + 1))
        fi
        if [ "$REPO_ACTUAL" -lt "$REPO_MAX" ]; then
            SURPLUS=$((SURPLUS + REPO_MAX - REPO_ACTUAL))
            REPO_MAX=$REPO_ACTUAL
        else
            DEFICIT_COUNT=$((DEFICIT_COUNT + 1))
        fi
        if [ "$BRANCH_ACTUAL" -lt "$BRANCH_MAX" ]; then
            SURPLUS=$((SURPLUS + BRANCH_MAX - BRANCH_ACTUAL))
            BRANCH_MAX=$BRANCH_ACTUAL
        else
            DEFICIT_COUNT=$((DEFICIT_COUNT + 1))
        fi

        # Pass 2: distribute surplus evenly to segments that need more space
        if [ "$DEFICIT_COUNT" -gt 0 ] && [ "$SURPLUS" -gt 0 ]; then
            EXTRA=$((SURPLUS / DEFICIT_COUNT))
            [ "$DIR_ACTUAL" -ge "$DIR_MAX" ] && DIR_MAX=$((DIR_MAX + EXTRA))
            [ "$REPO_ACTUAL" -ge "$REPO_MAX" ] && REPO_MAX=$((REPO_MAX + EXTRA))
            [ "$BRANCH_ACTUAL" -ge "$BRANCH_MAX" ] && BRANCH_MAX=$((BRANCH_MAX + EXTRA))
        fi

        # Apply truncation
        DIR_TRUNC=$(truncate "$DIR" "$DIR_MAX")
        ORG_REPO_TRUNC=$(truncate "$ORG_REPO" "$REPO_MAX")
        BRANCH_TRUNC=$(truncate "$BRANCH" "$BRANCH_MAX")

        # OSC 8 clickable link: \e]8;;URL\a TEXT \e]8;;\a
        GIT_PART="🔗 $(printf '%b' "\e]8;;${REMOTE}\a${ORG_REPO_TRUNC}\e]8;;\a")   🌿 ${BRANCH_TRUNC}${GIT_STATUS}"
    else
        # No remote — just branch + status; allocate more to dir and branch
        CHROME_WIDTH=10
        GIT_STATUS_WIDTH=$GIT_STATUS_LEN
        BUDGET=$((TERM_WIDTH - CHROME_WIDTH - GIT_STATUS_WIDTH))
        DIR_MAX=$((BUDGET * 55 / 100))
        BRANCH_MAX=$((BUDGET * 45 / 100))
        [ "$DIR_MAX" -lt 10 ] && DIR_MAX=10
        [ "$BRANCH_MAX" -lt 10 ] && BRANCH_MAX=10

        # Smart reallocation for 2-segment case
        DIR_ACTUAL=${#DIR}
        BRANCH_ACTUAL=${#BRANCH}
        if [ "$DIR_ACTUAL" -lt "$DIR_MAX" ] && [ "$BRANCH_ACTUAL" -gt "$BRANCH_MAX" ]; then
            BRANCH_MAX=$((BRANCH_MAX + DIR_MAX - DIR_ACTUAL))
            DIR_MAX=$DIR_ACTUAL
        elif [ "$BRANCH_ACTUAL" -lt "$BRANCH_MAX" ] && [ "$DIR_ACTUAL" -gt "$DIR_MAX" ]; then
            DIR_MAX=$((DIR_MAX + BRANCH_MAX - BRANCH_ACTUAL))
            BRANCH_MAX=$BRANCH_ACTUAL
        fi

        DIR_TRUNC=$(truncate "$DIR" "$DIR_MAX")
        BRANCH_TRUNC=$(truncate "$BRANCH" "$BRANCH_MAX")
        GIT_PART="🌿 ${BRANCH_TRUNC}${GIT_STATUS}"
    fi
fi

# Line 1: path, repo link, branch (truncated to fit terminal width)
if [ -n "$GIT_PART" ]; then
    printf '%b\n' "📁 ${DIR_TRUNC:-$DIR}   ${GIT_PART}"
else
    DIR_TRUNC=$(truncate "$DIR" $((TERM_WIDTH - 3)))
    echo "📁 ${DIR_TRUNC}"
fi

# Line 2: context, model, cost, api time, wall time, session
# Truncate session ID to first 8 chars to save space
SESSION_SHORT="${SESSION_ID:0:8}"

# Build line 2 and check if it fits; progressively drop less important fields if too wide
LINE2_FULL="🧠 ${USED_K}k/${CTX_K}k (${PCT_FMT}%)   🤖 ${MODEL_ID}   💰 ${COST_FMT}   ⚙️ ${API_MINS}m${API_SECS}s   📅 ${WALL_MINS}m${WALL_SECS}s   📋 ${SESSION_SHORT}"
LINE2_NO_SESSION="🧠 ${USED_K}k/${CTX_K}k (${PCT_FMT}%)   🤖 ${MODEL_ID}   💰 ${COST_FMT}   ⚙️ ${API_MINS}m${API_SECS}s   📅 ${WALL_MINS}m${WALL_SECS}s"
LINE2_NO_WALL="🧠 ${USED_K}k/${CTX_K}k (${PCT_FMT}%)   🤖 ${MODEL_ID}   💰 ${COST_FMT}   ⚙️ ${API_MINS}m${API_SECS}s"
LINE2_COMPACT="🧠 ${USED_K}k/${CTX_K}k (${PCT_FMT}%)   🤖 ${MODEL_ID}   💰 ${COST_FMT}"
LINE2_MINIMAL="🧠 ${USED_K}k/${CTX_K}k (${PCT_FMT}%)   🤖 ${MODEL_ID}"

if [ "${#LINE2_FULL}" -le "$TERM_WIDTH" ]; then
    echo "$LINE2_FULL"
elif [ "${#LINE2_NO_SESSION}" -le "$TERM_WIDTH" ]; then
    echo "$LINE2_NO_SESSION"
elif [ "${#LINE2_NO_WALL}" -le "$TERM_WIDTH" ]; then
    echo "$LINE2_NO_WALL"
elif [ "${#LINE2_COMPACT}" -le "$TERM_WIDTH" ]; then
    echo "$LINE2_COMPACT"
else
    echo "$LINE2_MINIMAL"
fi

