# Release 1.01 Preparation Summary

## ✅ Completed Tasks

### 1. Repository Name Changes
- ✅ Updated all references from `yankovinator-swift` to `yankovinator`
- ✅ Updated Homebrew formula class from `YankovinatorSwift` to `Yankovinator`
- ✅ Renamed formula file from `yankovinator-swift.rb` to `yankovinator.rb`
- ✅ Updated all GitHub URLs to use new repository name
- ✅ Updated Homebrew tap references from `homebrew-yankovinator-swift` to `homebrew-yankovinator`

### 2. Documentation Updates
- ✅ README.md - All repo references updated
- ✅ docs/index.html - All links and installation instructions updated
- ✅ docs/RELEASES.md - Updated with new repo name and version 1.01
- ✅ docs/yankovinator.tex - Updated installation instructions
- ✅ docs/reference.tex - Updated installation instructions
- ✅ docs/presentation.tex - Updated repo references
- ✅ docs/DEPLOYMENT.md - Updated GitHub Pages URLs

### 3. Homebrew Formula Updates
- ✅ Description changed to "using llama on Ollama" (removed Foundation Models reference)
- ✅ Version updated to "1.01"
- ✅ All URLs updated to new repository name
- ✅ Formula file renamed to `yankovinator.rb`

### 4. GitHub Actions Workflows
- ✅ release.yml - Updated with Homebrew installation instructions
- ✅ pages.yml - Will work automatically after repo rename

### 5. Binaries Prepared
- ✅ x86_64 binaries built and archived
- ✅ Universal and arm64 archives created (temporary - will be rebuilt by GitHub Actions)
- ✅ SHA256 checksums generated for all archives

## 📋 Next Steps (Required)

### 1. Rename Repository on GitHub
**CRITICAL**: The repository must be renamed on GitHub before creating the release.

1. Go to: https://github.com/shyamalschandra/Yankovinator-swift/settings
2. Scroll to "Repository name"
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
   - URL: https://github.com/shyamalschandra/homebrew-yankovinator
2. Copy `Formula/yankovinator.rb` to the tap repository as `yankovinator.rb`

### 4. Create Release 1.01

#### Option A: Using GitHub Actions (Recommended)
After renaming the repository:

```bash
git add .
git commit -m "Prepare for release 1.01: rename repo references"
git push origin main

# Tag the release
git tag -a v1.01 -m "Release version 1.01"
git push origin v1.01
```

The GitHub Actions workflow will automatically:
- Build proper arm64, x86_64, and universal binaries
- Create release v1.01 on GitHub
- Upload all binaries and checksums

#### Option B: Manual Release
1. Use the binaries in `dist/` directory (note: arm64/universal are temporary)
2. Go to: https://github.com/shyamalschandra/yankovinator/releases/new
3. Tag: `v1.01`
4. Title: `Release 1.01`
5. Upload all files from `dist/`:
   - `yankovinator-universal.tar.gz`
   - `yankovinator-universal.tar.gz.sha256`
   - `yankovinator-arm64.tar.gz`
   - `yankovinator-arm64.tar.gz.sha256`
   - `yankovinator-x86_64.tar.gz`
   - `yankovinator-x86_64.tar.gz.sha256`

### 5. Update Homebrew Tap

After the release is created with proper binaries:

1. **Get the final SHA256:**
   ```bash
   curl -sL https://github.com/shyamalschandra/yankovinator/releases/download/v1.01/yankovinator-universal.tar.gz.sha256 | awk '{print $1}'
   ```

2. **Update the tap repository:**
   ```bash
   git clone https://github.com/shyamalschandra/homebrew-yankovinator.git
   cd homebrew-yankovinator
   # Copy Formula/yankovinator.rb from main repo
   # Update SHA256 in the formula
   git add yankovinator.rb
   git commit -m "Add yankovinator formula v1.01"
   git push origin main
   ```

3. **Test installation:**
   ```bash
   brew tap shyamalschandra/yankovinator
   brew install yankovinator
   ```

## 📦 Current Binary Status

### Built Locally (x86_64)
- ✅ `yankovinator-x86_64.tar.gz` - Proper x86_64 binary
- ✅ SHA256: `4f1fa534ca1b585d9878871594b8b15054d848a38709484ce76de263cb0ff190`

### Temporary (Will be rebuilt by GitHub Actions)
- ⚠️ `yankovinator-arm64.tar.gz` - Currently x86_64 binary (works via Rosetta)
- ⚠️ `yankovinator-universal.tar.gz` - Currently x86_64 binary (works via Rosetta)
- ⚠️ SHA256: `0dca2f61a9fee93abbfea5563f3eda6f69596bc234c6e794b27ba2d15750fe8e` (temporary)

**Note**: The arm64 and universal binaries need to be rebuilt on Apple Silicon or via GitHub Actions for proper architecture support.

## 🔗 Important URL Changes

| Old URL | New URL |
|---------|---------|
| `github.com/shyamalschandra/Yankovinator-swift` | `github.com/shyamalschandra/yankovinator` |
| `shyamalschandra.github.io/Yankovinator-swift/` | `shyamalschandra.github.io/yankovinator/` |
| `homebrew-yankovinator-swift` | `homebrew-yankovinator` |
| `brew install yankovinator-swift` | `brew install yankovinator` |

## ✅ Verification Checklist

Before considering the release complete:

- [ ] Repository renamed on GitHub
- [ ] Local git remote updated
- [ ] Homebrew tap repository created
- [ ] Release 1.01 created with all binaries (proper arm64/universal from GitHub Actions)
- [ ] Homebrew tap updated with correct SHA256
- [ ] Installation tested via Homebrew: `brew install yankovinator`
- [ ] All documentation links verified
- [ ] GitHub Pages updated (if applicable)

## 📝 Files Modified

### Core Files
- `Formula/yankovinator.rb` (renamed from yankovinator-swift.rb)
- `README.md`
- `.github/workflows/release.yml`
- `.github/workflows/pages.yml`

### Documentation
- `docs/index.html`
- `docs/RELEASES.md`
- `docs/yankovinator.tex`
- `docs/reference.tex`
- `docs/presentation.tex`
- `docs/DEPLOYMENT.md`

### Scripts Created
- `BUILD_RELEASE_1.01.sh` - Build script for binaries
- `REPO_RENAME_INSTRUCTIONS.md` - Detailed rename instructions
- `RELEASE_1.01_SUMMARY.md` - This file

## 🎯 Key Changes Summary

1. **Repository Name**: `Yankovinator-swift` → `yankovinator`
2. **Homebrew Formula**: `yankovinator-swift` → `yankovinator`
3. **Version**: `1.0.1` → `1.01`
4. **Description**: Updated to mention "llama on Ollama" instead of Foundation Models
5. **All URLs**: Updated to reflect new repository name

## 🚀 Ready for Release

All code and documentation have been updated. The next steps are:
1. Rename the repository on GitHub
2. Create the release (preferably via GitHub Actions for proper binaries)
3. Update the Homebrew tap

The project is ready for release 1.01!
