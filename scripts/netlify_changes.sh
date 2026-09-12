#!/usr/bin/env bash
# What changed since Netlify last built, for two decisions that must not be confused:
#
#   ignore        exit 0 = nothing that ships changed: Netlify skips the build (netlify.toml)
#                 exit 1 = build
#   data-changed  exit 0 = tool/data/ changed, or that cannot be established: the extract's age
#                          limit is ENFORCED
#                 exit 1 = tool/data/ is exactly what was last built: the age limit is reported
#                          as a warning, because this deploy cannot make the data any staler
#
# WHY. The 21-day age limit guards a DATA deploy -- a stale extract shipping under a fresh
# deploy. Applied to every push, it also blocked documentation commits and interface fixes once
# the data aged, which is a gate on the wrong thing. A documentation-only commit now does not
# build at all; an interface change over unchanged data builds with every other gate intact.
#
# FAIL SAFE IN BOTH DIRECTIONS. Whenever the comparison cannot be made -- no CACHED_COMMIT_REF
# (a first build, a cleared cache, a local run), the same commit rebuilt, or a commit missing
# from the clone -- the answers are "build" and "data changed". An unknown never skips a build
# and never relaxes a gate.
set -uo pipefail

# Everything that ends up in, or decides, the published site.
SHIPS=(tool netlify.toml scripts/netlify_build.sh scripts/netlify_changes.sh
       scripts/check_extract.py scripts/test_tool_render.js)

comparable() {
  [ -n "${CACHED_COMMIT_REF:-}" ] && [ -n "${COMMIT_REF:-}" ] || return 1
  [ "$CACHED_COMMIT_REF" != "$COMMIT_REF" ] || return 1
  git cat-file -e "${CACHED_COMMIT_REF}^{commit}" 2>/dev/null || return 1
  git cat-file -e "${COMMIT_REF}^{commit}" 2>/dev/null || return 1
}

span() { echo "${CACHED_COMMIT_REF:0:7}..${COMMIT_REF:0:7}"; }

case "${1:-}" in
  ignore)
    if comparable && git diff --quiet "$CACHED_COMMIT_REF" "$COMMIT_REF" -- "${SHIPS[@]}"; then
      echo "netlify_changes: nothing that ships changed in $(span); skipping the build"
      exit 0
    fi
    echo "netlify_changes: building"
    exit 1
    ;;
  data-changed)
    if comparable && git diff --quiet "$CACHED_COMMIT_REF" "$COMMIT_REF" -- tool/data; then
      echo "netlify_changes: tool/data/ unchanged in $(span)"
      exit 1
    fi
    echo "netlify_changes: tool/data/ changed, or the change could not be established"
    exit 0
    ;;
  *)
    echo "usage: netlify_changes.sh ignore|data-changed" >&2
    exit 2
    ;;
esac
