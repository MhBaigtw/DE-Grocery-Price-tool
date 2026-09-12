#!/usr/bin/env bash
# Netlify build: gate the extract, then assemble the site. Runs on Netlify's builder and
# locally (see the bottom of this file for the local invocation).
#
# THE GATE RUNS FIRST, AND ITS FAILURE IS THE BUILD'S FAILURE. That is the whole point of
# putting it here rather than in a workflow: a refused extract must never reach the CDN, and
# on Netlify the only way to stop that is to exit non-zero before the publish directory is
# assembled. If check_extract.py says no, there is nothing to publish and the previous deploy
# stays live -- which is exactly the behaviour brief 4.3 and 5.3 ask for.
#
# WHAT THIS DOES NOT DO: verify the deployed site. That needs the live URL and therefore has
# to run after the deploy, not during it. scripts/verify_deploy.py does it, including the
# compression check, which is a property of the host and cannot be established from here.
set -euo pipefail

# Pick an interpreter that actually RUNS, not merely one that is on PATH. Windows ships a
# `python3` stub that prints an advert for the Microsoft Store and exits 0, which made the
# gate below appear to pass while executing nothing at all.
PY=""
for candidate in python3 python py; do
    if command -v "$candidate" >/dev/null 2>&1 &&
       "$candidate" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
        PY="$candidate"; break
    fi
done
[ -n "$PY" ] || { echo "FAILED: no working Python 3 on PATH"; exit 1; }

echo "=============================================================="
echo " context : ${CONTEXT:-local}"
echo " branch  : ${BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)}"
echo " python  : $("$PY" --version 2>&1)"
echo " node    : $(node --version 2>/dev/null || echo 'not present')"
echo "=============================================================="

# --- only main publishes ----------------------------------------------------------------
# Netlify's UI can disable branch deploys and deploy previews, and it should be set that way
# too. This is the belt to that braces: a build triggered from anywhere other than main stops
# here rather than becoming a public URL that looks like the real tool.
if [ -n "${CONTEXT:-}" ] && [ "${CONTEXT}" != "production" ]; then
    echo
    echo "REFUSED: context is '${CONTEXT}', not 'production'."
    echo "Only main publishes this site. A branch deploy or deploy preview would put an"
    echo "unreviewed extract on a public URL that looks like the tool. Turn branch deploys"
    echo "and deploy previews off in the Netlify UI; this check is the backstop."
    exit 1
fi

# Clear the publish directory before anything else. If a gate below refuses, there must be
# no _site left over from a previous run for anyone -- or anything -- to publish.
rm -rf _site

# --- 1. the deploy gate ------------------------------------------------------------------
echo
echo "--- extract gate -------------------------------------------------"
"$PY" scripts/check_extract.py

# --- 2. the interface must not betray what the extract enforces --------------------------
if command -v node >/dev/null 2>&1; then
    echo
    echo "--- render gate --------------------------------------------------"
    node scripts/test_tool_render.js
else
    echo "WARNING: node not present, skipping the render gate."
fi

# --- 3. assemble ---------------------------------------------------------------------------
echo
echo "--- assembling _site ---------------------------------------------"
mkdir -p _site
cp -r tool/. _site/
# The Phase 3 dashboard is NOT published (2026-09-12). Its pairwise chart compares
# Save-On-Foods, priced in Kamloops, BC, against Toronto chains -- the cross-city comparison
# withdrawn as W6. It stays in the repository as a record and comes back only once it is
# rebuilt without that comparison.

# The tool's own CNAME (if one is ever added) belongs to GitHub Pages, not Netlify, where a
# custom domain is configured in the UI. Shipping it would do nothing but confuse a reader.
rm -f _site/CNAME

# Fail loudly rather than publishing a shell with no data in it.
for f in index.html data/meta.json data/products.json data/history.json; do
    [ -s "_site/$f" ] || { echo "MISSING or empty: _site/$f"; exit 1; }
done

echo
du -sh _site 2>/dev/null || true
find _site -maxdepth 2 -type f | sort
echo
echo "OK - gates passed and _site is assembled."

# Local use:
#   bash scripts/netlify_build.sh
# CONTEXT is unset locally, so the production guard is skipped and the gates still run.
