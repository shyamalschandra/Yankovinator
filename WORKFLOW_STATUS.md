> **Current status (2026):** Yankovinator ships with **Ollama** (`llama3.2:3b`), not Apple Foundation Models. Treat the Foundation Models content below as historical / aspirational. Use [README.md](README.md) and [QUICK_START.md](QUICK_START.md) for accurate instructions.

# GitHub Actions Workflow Status

## ✅ Fixed Issues

### Swift Version Issue
- **Problem**: Swift version "6.2" not available in GitHub Actions
- **Solution**: Updated to Swift "6.0" (compatible with swift-tools-version: 6.2)
- **Status**: ✅ Fixed and committed

## Current Configuration

### Workflow Settings
- **Swift Version**: 6.0 (compatible with Package.swift requirement of 6.2)
- **macOS Runner**: macos-14 (for build jobs)
- **Ubuntu Runner**: ubuntu-latest (for release job)

### Build Process
1. **Build Job** (macos-14):
   - Builds for arm64 (native)
   - Builds for x86_64 (via Rosetta)
   - Creates platform-specific archives

2. **Create Universal Job** (macos-14):
   - Combines arm64 and x86_64 binaries using `lipo`
   - Creates universal archives
   - Includes all 3 executables (yankovinator, keyword-generator, benchmark)

3. **Release Job** (ubuntu-latest):
   - Downloads binaries
   - Generates SHA256 checksums
   - Creates GitHub Release with all assets

## Important Notes

### macOS 14 vs macOS 15.0+ Requirement
- **Build Environment**: macOS 14 (GitHub Actions runner)
- **Runtime Requirement**: macOS 15.0+ (for Foundation Models)
- **Why This Works**: 
  - The build process compiles the code, which uses conditional compilation (`#if canImport(FoundationModels)`)
  - The binaries are built but Foundation Models functionality requires macOS 15.0+ at runtime
  - This is similar to building iOS apps on older macOS versions - the build succeeds, but features require newer OS versions

### Conditional Compilation
The code uses `#if canImport(FoundationModels)` which allows:
- ✅ Building on macOS 14 (framework not available, code compiles but skips Foundation Models)
- ✅ Running on macOS 15.0+ (framework available, full functionality)

## Expected Workflow Behavior

### Successful Build
1. ✅ Swift 6.0 setup succeeds
2. ✅ Code compiles (even if Foundation Models not available on runner)
3. ✅ Binaries created for both architectures
4. ✅ Universal binaries created
5. ✅ Release created with all assets

### Runtime Behavior
- Binaries built on macOS 14 will work on macOS 15.0+ systems
- Foundation Models will be available at runtime on macOS 15.0+
- Tests gracefully skip Foundation Models features when unavailable

## Monitoring

### Check Workflow Status
- **Actions Tab**: https://github.com/shyamalschandra/Yankovinator-swift/actions
- **Latest Run**: Should show "Build and Release" workflow
- **Expected Duration**: 5-10 minutes

### If Build Fails
1. Check Swift version compatibility
2. Verify Foundation Models import (should be conditional)
3. Check for any missing dependencies
4. Review build logs for specific errors

## Release Assets

Once workflow completes, the release will include:
- `yankovinator-universal.tar.gz` (recommended)
- `yankovinator-arm64.tar.gz`
- `yankovinator-x86_64.tar.gz`
- SHA256 checksum files for each

Each archive contains:
- `yankovinator` executable
- `keyword-generator` executable
- `benchmark` executable (if available)

## Next Steps After Workflow Completes

1. ✅ Verify release assets are uploaded
2. ✅ Download and test universal binary
3. ✅ Calculate SHA256 for Homebrew formula
4. ✅ Update Homebrew formula with version 2.0.0 and checksum
5. ✅ Test on macOS 15.0+ system

---

**Last Updated**: After fixing Swift version issue  
**Status**: ✅ Ready to build  
**Tag**: v2.0.0 (pushed)
