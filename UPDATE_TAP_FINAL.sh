#!/bin/bash
# Final script to update Homebrew tap with SHA256 once v1.0.1 release is ready
# Run this after the GitHub Actions workflow completes

set -e

VERSION="1.0.1"
TAP_REPO="homebrew-yankovinator-swift"
GITHUB_USER="shyamalschandra"

echo "🔍 Getting SHA256 for v${VERSION}..."

# Get SHA256 from release
SHA256=$(curl -sL "https://github.com/${GITHUB_USER}/Yankovinator-swift/releases/download/v${VERSION}/yankovinator-universal.tar.gz.sha256" | awk '{print $1}')

if [ -z "$SHA256" ] || [ ${#SHA256} -ne 64 ]; then
    echo "❌ Failed to get SHA256. Is the release ready?"
    echo "   Check: https://github.com/${GITHUB_USER}/Yankovinator-swift/releases/tag/v${VERSION}"
    exit 1
fi

echo "✅ SHA256: ${SHA256}"

# Clone or update tap
if [ ! -d "/tmp/${TAP_REPO}" ]; then
    echo "📦 Cloning tap repository..."
    cd /tmp
    git clone "https://github.com/${GITHUB_USER}/${TAP_REPO}.git"
    cd "${TAP_REPO}"
else
    echo "📦 Updating tap repository..."
    cd "/tmp/${TAP_REPO}"
    git pull origin main
fi

# Update SHA256 in formula
echo "📝 Updating formula..."
sed -i.bak "s/sha256 \"[^\"]*\"/sha256 \"${SHA256}\"/" Formula/yankovinator-swift.rb
rm -f Formula/yankovinator-swift.rb.bak

# Verify
if ! grep -q "sha256 \"${SHA256}\"" Formula/yankovinator-swift.rb; then
    echo "❌ Failed to update SHA256"
    exit 1
fi

echo "✅ Formula updated!"

# Commit and push
git add Formula/yankovinator-swift.rb
git commit -m "Update SHA256 for v${VERSION}

SHA256: ${SHA256}
Release: https://github.com/${GITHUB_USER}/Yankovinator-swift/releases/tag/v${VERSION}"

git push origin main

echo ""
echo "✅ Homebrew tap updated successfully!"
echo ""
echo "Test installation:"
echo "  brew untap ${GITHUB_USER}/yankovinator-swift 2>/dev/null || true"
echo "  brew tap ${GITHUB_USER}/yankovinator-swift"
echo "  brew install yankovinator-swift"
echo ""
