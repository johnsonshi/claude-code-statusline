# claude-code-statusline

A customizable two-line status bar script for [Claude Code](https://claude.com/claude-code) CLI that shows git status, context window usage, model info, cost tracking, and more.

## Screenshot

![claude-code-statusline in action](screenshot.png)

## Features

**Line 1 — Git & workspace (adaptive to terminal width):**
- 📁 Current working directory (with `~` shortening)
- 🔗 Clickable GitHub repo link ([OSC 8](https://en.wikipedia.org/wiki/ANSI_escape_code#OSC) — Cmd+click in iTerm2)
- 🌿 Git branch with oh-my-zsh style status symbols
- Smart truncation that adapts to terminal width so nothing gets cut off

**Line 2 — Session info (progressive graceful degradation):**
- 🧠 Context window usage derived from `used_percentage` (accurate, not cumulative)
- 🤖 Model ID
- 💰 Session cost
- ⚙️ API time
- 📅 Wall time
- 📋 Session ID (truncated to 8 chars)

Line 2 progressively drops less important fields (session ID → wall time → API time → cost) when the terminal is too narrow, ensuring context window and model info are always visible.

### Terminal-width-aware truncation

The status line detects your terminal width and intelligently truncates long paths, repo names, and branch names to fit. When one segment is shorter than its allocation, the surplus space is redistributed to segments that need it.

**Budget allocation (Line 1 with remote):**
| Segment | Base allocation | Notes |
|---------|----------------|-------|
| Directory path | 35% | e.g. `~/repos/my-project` |
| Org/repo | 30% | e.g. `johnsonshi/claude-code-statusline` |
| Branch name | 35% | e.g. `feature/add-terminal-width-truncation` |

Segments that don't use their full budget donate surplus to those that need it. Truncated values end with `…`.

**Graceful degradation (Line 2):**

| Terminal width | Fields shown |
|---------------|--------------|
| Wide | 🧠 context  🤖 model  💰 cost  ⚙️ api time  📅 wall time  📋 session |
| Medium | 🧠 context  🤖 model  💰 cost  ⚙️ api time  📅 wall time |
| Narrow | 🧠 context  🤖 model  💰 cost  ⚙️ api time |
| Compact | 🧠 context  🤖 model  💰 cost |
| Minimal | 🧠 context  🤖 model |

### Git status symbols

| Symbol | Meaning | Color |
|--------|---------|-------|
| ✚ | Staged files | Yellow |
| ✱ | Modified files (unstaged) | Yellow |
| ✖ | Deleted files (unstaged) | Yellow |
| ➜ | Renamed files (staged) | Yellow |
| ◼ | Untracked files | Yellow |
| ═ | Merge conflicts | Yellow |
| ⚡ | Stash entries | Default |
| ⬆ | Commits ahead of remote | Default |
| ⬇ | Commits behind remote | Default |

## Requirements

- [jq](https://jqlang.github.io/jq/) — for parsing JSON from stdin
- Git — for branch/status info
- A terminal that supports OSC 8 for clickable links (iTerm2, Kitty, WezTerm)

## Installation

1. Copy the script to your Claude config directory:

```bash
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

2. Add the following to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

3. The status line will appear after your next interaction with Claude Code.

## How it works

Claude Code pipes JSON session data to the script via stdin on every update (after each assistant message, debounced at 300ms). The script extracts fields with `jq`, runs cached git commands, and prints two lines to stdout.

Git operations (branch, status, remote URL) are cached to `/tmp/statusline-git-cache` with a 5-second TTL to avoid lag in large repositories.

The script detects the terminal width via `tput cols` and uses proportional budget allocation with surplus redistribution to truncate long directory paths, repo names, and branch names so that all information remains visible. Line 2 uses progressive graceful degradation to drop less important fields when space is limited.

For full details on the status line API, see the [Claude Code statusline docs](https://code.claude.com/docs/en/statusline).

## Testing

Test with mock JSON input:

```bash
echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus"},"workspace":{"current_dir":"/Users/you/project"},"cost":{"total_cost_usd":0.05,"total_api_duration_ms":30000},"context_window":{"context_window_size":200000,"used_percentage":25.0},"session_id":"test123"}' | ./statusline.sh
```

Test with a narrow terminal to see truncation in action:

```bash
# Simulate a narrow terminal (80 columns)
echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus"},"workspace":{"current_dir":"/Users/you/very-long-workspace-directory-name/deeply-nested/project"},"cost":{"total_cost_usd":0.05,"total_api_duration_ms":30000},"context_window":{"context_window_size":200000,"used_percentage":25.0},"session_id":"test123"}' | COLUMNS=80 ./statusline.sh
```

## License

MIT
