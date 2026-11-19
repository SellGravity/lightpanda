#!/usr/bin/env bash
# Packs a CI-built InviPanda (static V8, embedded snapshot) for the launcher:
#   dist/invipanda-<os>-<arch>.tar.gz  ->  invipanda/{invipanda,lightpanda,...}
#
#   scripts/invipanda-package-ci.sh <os> <arch> <binary>
set -euo pipefail
cd "$(dirname "$0")/.."

OS="$1"
ARCH="$2"
BIN="$3"

OUT=dist/invipanda
rm -rf "$OUT" && mkdir -p "$OUT"
cp "$BIN" "$OUT/lightpanda"
cat > "$OUT/invipanda" <<'EOF'
#!/bin/sh
# InviPanda launcher (SellGravity/lightpanda antidetect build).
DIR="$(cd "$(dirname "$0")" && pwd)"
export LIGHTPANDA_DISABLE_TELEMETRY=true
exec "$DIR/lightpanda" "$@"
EOF
chmod +x "$OUT/invipanda" "$OUT/lightpanda"
cp ANTIDETECT_PLAN.md LICENSE "$OUT/"
"$OUT/lightpanda" version > "$OUT/VERSION"
tar -C dist -czf "dist/invipanda-$OS-$ARCH.tar.gz" invipanda
shasum -a 256 "dist/invipanda-$OS-$ARCH.tar.gz" | tee "dist/invipanda-$OS-$ARCH.tar.gz.sha256"
