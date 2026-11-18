#!/usr/bin/env bash
# Builds a ReleaseFast InviPanda and packs it with its V8 runtime library and
# a launcher script into dist/invipanda-linux-x86_64.tar.gz.
#
#   make download-v8 && scripts/invipanda-package.sh
set -euo pipefail
cd "$(dirname "$0")/.."

zig build -Doptimize=ReleaseFast

V8_SO=$(find .lp-cache -name 'libc_v8.so' | head -1)
if [ -z "$V8_SO" ]; then
  echo "libc_v8.so not found: run 'make download-v8' first" >&2
  exit 1
fi

OUT=dist/invipanda
rm -rf "$OUT" && mkdir -p "$OUT"
cp zig-out/bin/lightpanda "$OUT/lightpanda"
cp "$V8_SO" "$OUT/libc_v8.so"
cat > "$OUT/invipanda" <<'EOF'
#!/usr/bin/env bash
# InviPanda launcher: the bundled V8 library sits next to the binary.
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
export LD_LIBRARY_PATH="$DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LIGHTPANDA_DISABLE_TELEMETRY=true
exec "$DIR/lightpanda" "$@"
EOF
chmod +x "$OUT/invipanda" "$OUT/lightpanda"
cp ANTIDETECT_PLAN.md LICENSE "$OUT/"
tar -C dist -czf dist/invipanda-linux-x86_64.tar.gz invipanda
ls -la dist/invipanda-linux-x86_64.tar.gz
