#!/bin/bash
# Update the Homebrew tap for the latest Yankovinator release.
# Usage: ./update-homebrew-tap.sh [version]
# Example: ./update-homebrew-tap.sh 1.02

set -euo pipefail

VERSION="${1:-1.04.7}"
TAG="v${VERSION}"
GITHUB_USER="shyamalschandra"
MAIN_REPO="Yankovinator"
TAP_REPO="homebrew-yankovinator"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TAP_DIR="${SCRIPT_DIR}/../${TAP_REPO}"

echo "Updating Homebrew tap for ${TAG}"

if [ ! -d "${TAP_DIR}/.git" ]; then
  git clone "https://github.com/${GITHUB_USER}/${TAP_REPO}.git" "${TAP_DIR}"
else
  git -C "${TAP_DIR}" pull --ff-only origin main
fi

SHA_URL="https://github.com/${GITHUB_USER}/${MAIN_REPO}/releases/download/${TAG}/yankovinator-universal.tar.gz.sha256"
SHA256="$(curl -fsSL "${SHA_URL}" | awk '{print $1}')"
if [ -z "${SHA256}" ]; then
  echo "Failed to fetch SHA256 from ${SHA_URL}"
  exit 1
fi

echo "SHA256: ${SHA256}"

cp "${SCRIPT_DIR}/Formula/yankovinator.rb" "${TAP_DIR}/yankovinator.rb"

# Keep tap formula URL/sha synced to the requested release.
python3 - <<PY
from pathlib import Path
import re
path = Path("${TAP_DIR}/yankovinator.rb")
text = path.read_text()
text = re.sub(
    r"https://github.com/shyamalschandra/Yankovinator/releases/download/v[0-9.]+/yankovinator-universal.tar.gz",
    f"https://github.com/shyamalschandra/Yankovinator/releases/download/v${VERSION}/yankovinator-universal.tar.gz",
    text,
    count=1,
)
text = re.sub(r'sha256 "[^"]+"', f'sha256 "${SHA256}"', text, count=1)
path.write_text(text)
PY

git -C "${TAP_DIR}" add yankovinator.rb
if git -C "${TAP_DIR}" diff --cached --quiet; then
  echo "Tap already up to date for ${TAG}"
  exit 0
fi

git -C "${TAP_DIR}" commit -m "Update Yankovinator formula to ${TAG}

Release: https://github.com/${GITHUB_USER}/${MAIN_REPO}/releases/tag/${TAG}"
git -C "${TAP_DIR}" push origin HEAD

echo
echo "Tap updated. Install with:"
echo "  brew tap ${GITHUB_USER}/yankovinator"
echo "  brew install yankovinator"
