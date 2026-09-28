#!/usr/bin/env bash
# Regenerates the Swift API client (CopilotAPI) from api/openapi.yaml - the contract shared with the backend.
# Run after every change of api/openapi.yaml, then commit the regenerated files.
#  apple/scripts/generate-api.sh          # regenerate
#  apple/scripts/generate-api.sh --check  # fail if the committed code is out of date (for CI)
set -euo pipefail

PACKAGE="$(cd "$(dirname "$0")/../Packages/CopilotKit" && pwd)"
TARGET="$PACKAGE/Sources/CopilotAPI"
OUT="$TARGET/GeneratedSources"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The generator runs as a command-line tool from the package dependency (no global install needed).
swift run --package-path "$PACKAGE" swift-openapi-generator generate \
 "$TARGET/openapi.yaml" \
 --config "$TARGET/openapi-generator-config.yaml" \
 --output-directory "$TMP" >/dev/null

if [ "${1:-}" = "--check" ]; then
 diff -r "$TMP" "$OUT" >/dev/null || { echo "CopilotAPI is out of date: run apple/scripts/generate-api.sh" >&2; exit 1; }
 echo "CopilotAPI is up to date"
else
 rm -rf "$OUT" && mkdir -p "$OUT" && cp "$TMP"/*.swift "$OUT/"
 echo "Regenerated $(ls "$OUT" | wc -l | tr -d ' ') files in $OUT"
fi
