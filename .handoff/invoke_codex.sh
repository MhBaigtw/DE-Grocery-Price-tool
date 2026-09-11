#!/usr/bin/env bash
# Hand this project over to Codex with the context it needs to not guess.
#
# The checks below exist because the two things a handoff actually loses are uncommitted
# work and a stale note. Neither is visible to the agent picking up — it sees a clean-looking
# repository and a confident document, and has no way to know the document describes a state
# three commits ago. So both are checked here, loudly, before the agent is ever started.
#
# Usage:  ./.handoff/invoke_codex.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

NOTE=".handoff/latest_handoff.md"
RESUME="docs/RESUME.md"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }

confirm() {
    # Refuse to continue on a non-interactive run rather than assuming yes. An unattended
    # handoff that silently proceeds past a dirty tree is the exact failure this guards.
    if [ ! -t 0 ]; then
        red "Not an interactive terminal, so this cannot be confirmed. Aborting."
        exit 1
    fi
    printf '%s [y/N] ' "$1"
    read -r reply
    case "$reply" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) echo "Aborted."; exit 1 ;;
    esac
}

# --- 1. The handoff note must exist -----------------------------------------------------
if [ ! -f "$NOTE" ]; then
    red "No handoff note at $NOTE"
    echo
    echo "There is nothing to hand over. Write the note first:"
    echo "  cp .handoff/context_template.md $NOTE"
    echo "and fill it in. An empty template is worse than no note, because the next agent"
    echo "will read it as though it were true."
    exit 1
fi

if [ ! -f "$RESUME" ]; then
    red "No $RESUME — the note tells the agent to read it and it is not there."
    exit 1
fi

# --- 2. Uncommitted work is the main thing a handoff loses ------------------------------
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    warn "Not a git repository. Skipping the tree and staleness checks."
else
    if [ -n "$(git status --porcelain)" ]; then
        echo
        red "=================================================================="
        red " THE WORKING TREE IS NOT CLEAN."
        red "=================================================================="
        echo
        echo "Uncommitted work is the one thing a handoff genuinely destroys. The next"
        echo "agent sees the commits, not your working tree, and will not know this exists."
        echo
        git status --short
        echo
        echo "Commit it, or describe every one of these files in $NOTE under"
        echo "\"Last commit\" — what it is, and why it is not committed."
        echo
        confirm "Continue anyway?"
    else
        ok "Working tree is clean."
    fi

    # --- 3. A note older than the last commit describes a state that has moved on -------
    LAST_COMMIT_EPOCH="$(git log -1 --format=%ct 2>/dev/null || echo 0)"
    if [ -f "$NOTE" ] && [ "$LAST_COMMIT_EPOCH" != "0" ]; then
        if command -v stat >/dev/null 2>&1; then
            NOTE_EPOCH="$(stat -c %Y "$NOTE" 2>/dev/null || stat -f %m "$NOTE" 2>/dev/null || echo 0)"
        else
            NOTE_EPOCH=0
        fi
        if [ "$NOTE_EPOCH" != "0" ] && [ "$NOTE_EPOCH" -lt "$LAST_COMMIT_EPOCH" ]; then
            echo
            red "=================================================================="
            red " THE HANDOFF NOTE IS OLDER THAN THE LAST COMMIT."
            red "=================================================================="
            echo
            echo "  note written : $(date -d "@$NOTE_EPOCH" 2>/dev/null || date -r "$NOTE_EPOCH" 2>/dev/null)"
            echo "  last commit  : $(git log -1 --format='%cd  %h  %s')"
            echo
            echo "The note describes a state the repository has moved past. The next agent"
            echo "will read it as current and be misled by it. Rewrite it in full from"
            echo ".handoff/context_template.md before handing over."
            echo
            confirm "Continue with a stale note anyway?"
        else
            ok "Handoff note is at least as new as the last commit."
        fi
    fi

    # Worth seeing, not worth blocking on.
    UNPUSHED="$(git log --oneline @{u}..HEAD 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${UNPUSHED:-0}" != "0" ]; then
        warn "$UNPUSHED commit(s) not pushed to the upstream branch."
    fi
fi

# --- 4. Hand over ------------------------------------------------------------------------
if ! command -v codex >/dev/null 2>&1; then
    red "codex is not on PATH."
    echo "Install it, or run the prompt below in whatever agent you are handing over to."
    echo
fi

PROMPT='Context handoff. Read docs/RESUME.md and follow it before doing anything.
Then read .handoff/latest_handoff.md for where work stopped. Verify state and
report before resuming.'

echo
ok "Handing over with:"
printf '%s\n\n' "$PROMPT"

command -v codex >/dev/null 2>&1 || exit 1
exec codex "$PROMPT"
