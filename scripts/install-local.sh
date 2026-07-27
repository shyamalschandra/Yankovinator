#!/usr/bin/env bash
# Build release binaries + Rust TUI and install over Homebrew or ~/.local/bin
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEST="${1:-}"
if [[ -z "$DEST" ]]; then
  if command -v yankovinator >/dev/null 2>&1; then
    DEST="$(dirname "$(command -v yankovinator)")"
  else
    DEST="$HOME/.local/bin"
    mkdir -p "$DEST"
  fi
fi

echo "Building Swift release…"
swift build -c release

echo "Building yankovinator-tui (Rust)…"
if ! command -v cargo >/dev/null 2>&1; then
  echo "Error: cargo not found. Install Rust from https://rustup.rs" >&2
  exit 1
fi
( cd tui && cargo build --release )

Y="$ROOT/.build/release/yankovinator"
KG="$ROOT/.build/release/keyword-generator"
TUI="$ROOT/tui/target/release/yankovinator-tui"

for f in "$Y" "$KG" "$TUI"; do
  [[ -x "$f" ]] || { echo "Missing $f" >&2; exit 1; }
done

echo "Installing to $DEST"
cp "$Y" "$KG" "$TUI" "$DEST/"
chmod +x "$DEST/yankovinator" "$DEST/keyword-generator" "$DEST/yankovinator-tui"

echo ""
"$DEST/yankovinator" --version
echo "Help check: $( "$DEST/yankovinator" --help 2>&1 | rg -q 'fresh-batch' && echo 'OK (fresh-batch present)' || echo 'WARN missing fresh-batch' )"
echo "TUI: $DEST/yankovinator-tui"
