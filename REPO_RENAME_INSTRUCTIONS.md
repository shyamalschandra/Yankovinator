# Repository Rename Instructions: Yankovinator-swift → yankovinator

## Overview
This document outlines the steps needed to rename the repository from `Yankovinator-swift` to `yankovinator` and create release 1.01.

## Prerequisites
1. All code files have been updated with new repository references
2. Homebrew formula has been updated and renamed to `yankovinator.rb`
3. All documentation has been updated

## Steps to Rename Repository on GitHub

### 1. Rename the Repository
1. Go to: https://github.com/shyamalschandra/Yankovinator-swift/settings
2. Scroll to "Repository name" section
3. Change from `Yankovinator-swift` to `yankovinator`
4. Click "Rename"

### 2. Update Local Git Remote
```bash
cd /Users/shyamalchandra/Yankovinator-swift
git remote set-url origin https://github.com/shyamalschandra/yankovinator.git
git remote -v  # Verify
```

### 3. Create Homebrew Tap Repository
1. Create new repository: `homebrew-yankovinator`
2. URL: https://github.com/shyamalschandra/homebrew-yankovinator
3. Copy `Formula/yankovinator.rb` to the tap repository as `yankovinator.rb`

## Creating Release 1.01

### Option 1: Using GitHub Actions (Recommended)
After renaming the repository:

1. **Tag the release:**
   ```bash
   git tag -a v1.01 -m "Release version 1.01"
   git push origin v1.01
   ```

2. The GitHub Actions workflow will automatically:
   - Build binaries for arm64, x86_64, and universal
   - Create release v1.01 on GitHub
   - Upload all binaries and checksums

### Option 2: Manual Build and Release
If you prefer to build locally:

1. **Build for arm64:**
   ```bash
   swift build -c release
   mkdir -p dist/arm64
   cp .build/*/release/yankovinator dist/arm64/
   cp .build/*/release/keyword-generator dist/arm64/
   cp .build/*/release/benchmark dist/arm64/ 2>/dev/null || true
   ```

2. **Build for x86_64:**
   ```bash
   rm -rf .build
   arch -x86_64 swift build -c release
   mkdir -p dist/x86_64
   cp .build/*/release/yankovinator dist/x86_64/
   cp .build/*/release/keyword-generator dist/x86_64/
   cp .build/*/release/benchmark dist/x86_64/ 2>/dev/null || true
   ```

3. **Create universal binaries:**
   ```bash
   mkdir -p dist/universal
   lipo -create dist/x86_64/yankovinator dist/arm64/yankovinator -output dist/universal/yankovinator
   lipo -create dist/x86_64/keyword-generator dist/arm64/keyword-generator -output dist/universal/keyword-generator
   if [ -f dist/x86_64/benchmark ] && [ -f dist/arm64/benchmark ]; then
     lipo -create dist/x86_64/benchmark dist/arm64/benchmark -output dist/universal/benchmark
   fi
   ```

4. **Create archives:**
   ```bash
   cd dist/universal && tar -czf ../yankovinator-universal.tar.gz yankovinator keyword-generator benchmark 2>/dev/null || tar -czf ../yankovinator-universal.tar.gz yankovinator keyword-generator
   cd ../arm64 && tar -czf ../yankovinator-arm64.tar.gz yankovinator keyword-generator benchmark 2>/dev/null || tar -czf ../yankovinator-arm64.tar.gz yankovinator keyword-generator
   cd ../x86_64 && tar -czf ../yankovinator-x86_64.tar.gz yankovinator keyword-generator benchmark 2>/dev/null || tar -czf ../yankovinator-x86_64.tar.gz yankovinator keyword-generator
   cd ../..
   ```

5. **Create checksums:**
   ```bash
   cd dist
   for file in *.tar.gz; do
     shasum -a 256 "$file" > "${file}.sha256"
   done
   ```

6. **Create GitHub Release:**
   - Go to: https://github.com/shyamalschandra/yankovinator/releases/new
   - Tag: `v1.01`
   - Title: `Release 1.01`
   - Upload all `.tar.gz` and `.sha256` files
   - Add release notes (see release.yml for template)

## Update Homebrew Tap

After the release is created:

1. **Get SHA256:**
   ```bash
   curl -sL https://github.com/shyamalschandra/yankovinator/releases/download/v1.01/yankovinator-universal.tar.gz.sha256 | awk '{print $1}'
   ```

2. **Update tap repository:**
   - Clone: `git clone https://github.com/shyamalschandra/homebrew-yankovinator.git`
   - Update `yankovinator.rb` with version `1.01` and SHA256
   - Commit and push

3. **Test installation:**
   ```bash
   brew tap shyamalschandra/yankovinator
   brew install yankovinator
   ```

## Verification Checklist

- [ ] Repository renamed on GitHub
- [ ] Local git remote updated
- [ ] Homebrew tap repository created
- [ ] Release 1.01 created with all binaries
- [ ] Homebrew tap updated with correct SHA256
- [ ] Installation tested via Homebrew
- [ ] All documentation links work
- [ ] GitHub Pages updated (if applicable)

## Important Notes

1. **GitHub Pages URL will change** from `shyamalschandra.github.io/Yankovinator-swift/` to `shyamalschandra.github.io/yankovinator/`
2. **All existing links** to the old repository will break - update any external references
3. **Homebrew tap name** changes from `homebrew-yankovinator-swift` to `homebrew-yankovinator`
4. **Formula class name** is now `Yankovinator` (not `YankovinatorSwift`)
5. **Installation command** changes from `brew install yankovinator-swift` to `brew install yankovinator`
