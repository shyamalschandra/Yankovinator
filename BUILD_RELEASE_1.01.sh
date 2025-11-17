#!/bin/bash
# Script to build binaries for release 1.01
# Note: This script builds x86_64 binaries. For arm64 and universal binaries,
# use GitHub Actions or build on an Apple Silicon Mac.

set -e

VERSION="1.01"
echo "🔨 Building binaries for release ${VERSION}..."

# Clean and prepare
rm -rf dist .build
mkdir -p dist/arm64 dist/x86_64 dist/universal

# Build for x86_64 (native on Intel Macs)
echo "📦 Building for x86_64..."
arch -x86_64 swift build -c release

# Copy x86_64 binaries
cp .build/*/release/yankovinator dist/x86_64/ 2>/dev/null || echo "Warning: yankovinator not found"
cp .build/*/release/keyword-generator dist/x86_64/ 2>/dev/null || echo "Warning: keyword-generator not found"
cp .build/*/release/benchmark dist/x86_64/ 2>/dev/null || echo "Note: benchmark not found"

# Make executable
chmod +x dist/x86_64/* 2>/dev/null || true

# Verify x86_64 binaries
echo "✅ x86_64 binaries:"
file dist/x86_64/* 2>/dev/null || true

# For arm64: Build on Apple Silicon or use GitHub Actions
if [[ $(uname -m) == "arm64" ]]; then
    echo "📦 Building for arm64 (native)..."
    rm -rf .build
    swift build -c release
    cp .build/*/release/yankovinator dist/arm64/ 2>/dev/null || echo "Warning: yankovinator not found"
    cp .build/*/release/keyword-generator dist/arm64/ 2>/dev/null || echo "Warning: keyword-generator not found"
    cp .build/*/release/benchmark dist/arm64/ 2>/dev/null || echo "Note: benchmark not found"
    chmod +x dist/arm64/* 2>/dev/null || true
    
    # Create universal binaries
    echo "📦 Creating universal binaries..."
    lipo -create dist/x86_64/yankovinator dist/arm64/yankovinator -output dist/universal/yankovinator
    lipo -create dist/x86_64/keyword-generator dist/arm64/keyword-generator -output dist/universal/keyword-generator
    if [ -f dist/x86_64/benchmark ] && [ -f dist/arm64/benchmark ]; then
        lipo -create dist/x86_64/benchmark dist/arm64/benchmark -output dist/universal/benchmark
    fi
    chmod +x dist/universal/* 2>/dev/null || true
else
    echo "⚠️  Running on Intel Mac - cannot build arm64 binaries locally"
    echo "   Use GitHub Actions to build arm64 and universal binaries"
    echo "   For now, copying x86_64 as universal (works via Rosetta)"
    cp dist/x86_64/* dist/universal/ 2>/dev/null || true
    cp dist/x86_64/* dist/arm64/ 2>/dev/null || true
fi

# Create archives
echo "📦 Creating archives..."
cd dist/universal
if [ -f benchmark ]; then
    tar -czf ../yankovinator-universal.tar.gz yankovinator keyword-generator benchmark
else
    tar -czf ../yankovinator-universal.tar.gz yankovinator keyword-generator
fi

cd ../arm64
if [ -f benchmark ]; then
    tar -czf ../yankovinator-arm64.tar.gz yankovinator keyword-generator benchmark
else
    tar -czf ../yankovinator-arm64.tar.gz yankovinator keyword-generator
fi

cd ../x86_64
if [ -f benchmark ]; then
    tar -czf ../yankovinator-x86_64.tar.gz yankovinator keyword-generator benchmark
else
    tar -czf ../yankovinator-x86_64.tar.gz yankovinator keyword-generator
fi

cd ../..

# Create checksums
echo "📝 Creating checksums..."
cd dist
for file in *.tar.gz; do
    if [ -f "$file" ]; then
        shasum -a 256 "$file" > "${file}.sha256"
        echo "✅ ${file}: $(cat ${file}.sha256 | awk '{print $1}')"
    fi
done
cd ..

echo ""
echo "✅ Build complete!"
echo ""
echo "📦 Binaries created in dist/:"
ls -lh dist/*.tar.gz dist/*.sha256 2>/dev/null || true
echo ""
echo "📋 Next steps:"
echo "1. Rename repository on GitHub: Yankovinator-swift → yankovinator"
echo "2. Create release v${VERSION} at: https://github.com/shyamalschandra/yankovinator/releases/new"
echo "3. Upload all .tar.gz and .sha256 files"
echo "4. Update Homebrew tap with SHA256 from yankovinator-universal.tar.gz.sha256"
echo ""
