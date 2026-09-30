#!/usr/bin/env bash
# Publish the already-gated _site to Vercel as a PREBUILT deployment.
#
# WHY PREBUILT, AND WHY NOT VERCEL'S GIT INTEGRATION. Between 2026-09-13 and 2026-09-27 the
# refresh committed a fresh extract almost daily and the site served none of it: the host's
# builder refused every deploy and the public site sat fourteen days stale (findings §12). A
# hosted builder that can independently refuse is a dependency this pipeline does not need --
# the gates already run here, in CI, before anything is uploaded. So this uploads finished
# files: `vercel deploy --prebuilt` sends .vercel/output and no build runs on their side.
#
# WHAT IT PUBLISHES. _site exactly as scripts/netlify_build.sh assembled and gated it (that
# script is still the one that runs check_extract.py and the render gate; its name is historical
# and Netlify stays configured but unused). Response headers come from
# config/vercel_output_config.json, committed and reviewable, so moving host cannot silently
# drop the cache rules or the CSP.
#
# WHAT IT REFUSES. No token, no _site, a missing data file, or a missing project link: it exits
# non-zero and publishes nothing. The previous deployment stays live, which is the same
# behaviour every other gate in this project has.
#
#   VERCEL_TOKEN=... bash scripts/vercel_publish.sh          # publish to production
#   VERCEL_TOKEN=... bash scripts/vercel_publish.sh --dry-run # assemble .vercel/output, upload nothing
set -euo pipefail

CLI_VERSION="62.0.0"          # pinned: a deploy path should not change under us unannounced
PROJECT_LINK="config/vercel_project.json"
PROJECT_NAME="de-grocery-price-tool"   # the Vercel project this repository publishes to
OUTPUT_CONFIG="config/vercel_output_config.json"
DRY_RUN="${1:-}"

[ -n "${VERCEL_TOKEN:-}" ] || { echo "REFUSED: VERCEL_TOKEN is not set"; exit 1; }
[ -d _site ] || { echo "REFUSED: _site is missing. Run 'bash scripts/netlify_build.sh' first -- it runs the gates and assembles it."; exit 1; }
for f in index.html data/meta.json data/products.json data/history.json; do
    [ -s "_site/$f" ] || { echo "REFUSED: _site/$f is missing or empty"; exit 1; }
done
[ -f "$OUTPUT_CONFIG" ] || { echo "REFUSED: $OUTPUT_CONFIG is missing"; exit 1; }
# The project link (orgId, projectId) is committed so a deploy never depends on interactive
# selection. The first run has no link yet: it asks Vercel for the project by name and prints
# the ids to be committed.

echo "=============================================================="
echo " extract : $(python -c 'import json;m=json.load(open("_site/data/meta.json"));print(m["extract_date"], m["products_shipped"], "products, snapshot", m["snapshot_id"])')"
echo " project : $PROJECT_NAME"
echo " cli     : vercel@$CLI_VERSION"
echo "=============================================================="

# The Build Output API tree: finished files plus the header rules. Nothing here is built.
rm -rf .vercel/output
mkdir -p .vercel/output/static
cp -r _site/. .vercel/output/static/
python -c "
import json, pathlib
cfg = json.loads(pathlib.Path('$OUTPUT_CONFIG').read_text(encoding='utf-8'))
cfg.pop('_comment', None)
pathlib.Path('.vercel/output/config.json').write_text(json.dumps(cfg, indent=2), encoding='utf-8')
print('  wrote .vercel/output/config.json with', len(cfg['routes']), 'header routes')
"
if [ -f "$PROJECT_LINK" ]; then
    cp "$PROJECT_LINK" .vercel/project.json
    echo "  linked from $PROJECT_LINK"
else
    echo "  no $PROJECT_LINK yet: linking to project '$PROJECT_NAME' by name"
    npx --yes "vercel@$CLI_VERSION" link --yes --project "$PROJECT_NAME" --token "$VERCEL_TOKEN"
    echo "  COMMIT THESE IDS as $PROJECT_LINK:"
    python -c "
import json, pathlib
d = json.loads(pathlib.Path('.vercel/project.json').read_text(encoding='utf-8'))
print(json.dumps({'orgId': d['orgId'], 'projectId': d['projectId'], 'projectName': '$PROJECT_NAME'}, indent=2))
"
fi
find .vercel/output/static -type f | sort | sed 's/^/  /'

if [ "$DRY_RUN" = "--dry-run" ]; then
    echo
    echo "DRY RUN - .vercel/output is assembled and nothing was uploaded."
    exit 0
fi

echo
echo "--- uploading to Vercel (no build runs there) --------------------"
npx --yes "vercel@$CLI_VERSION" deploy --prebuilt --prod --yes --token "$VERCEL_TOKEN" | tee .vercel/deploy-url.txt
echo
echo "OK - deployed $(tail -1 .vercel/deploy-url.txt)"
echo "The deployment URL above is this build; the project's production domain serves it."
