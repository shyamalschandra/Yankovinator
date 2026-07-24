> **Current status (2026):** Yankovinator ships with **Ollama** (`llama3.2:3b`), not Apple Foundation Models. Treat the Foundation Models content below as historical / aspirational. Use [README.md](README.md) and [QUICK_START.md](QUICK_START.md) for accurate instructions.

# GitHub Actions Version Compatibility Guide

## Swift Versions

### Available Swift Versions in `swift-actions/setup-swift@v1`

Based on testing and the action's default configuration:

**✅ Confirmed Working:**
- **Swift 5.10** - ✅ Currently working in our workflow
- **Swift 5.9** - ✅ Should work
- **Swift 5.8** - ✅ Should work

**✅ Confirmed Available (from source code):**
- **Swift 6.1.0** - ✅ AVAILABLE (listed first in swift-versions.ts)
- **Swift 6.0.3, 6.0.2, 6.0.1, 6.0.0, 6.0** - ✅ AVAILABLE (all listed in swift-versions.ts)

**❌ Not Available:**
- **Swift 6.2** - ❌ Not available (we tested this, not in swift-versions.ts)

**Recommendation:**
- **Use Swift 5.10** for maximum compatibility
- If you need Swift 6.x features, try **Swift 6.1.0** (the default)

### How to Check Available Versions

The `swift-actions/setup-swift` action downloads Swift from:
- Official Swift.org releases
- Xcode toolchains

To see what's actually available, check:
1. The action's default version: `6.1.0` (from action.yml)
2. Swift.org releases: https://swift.org/download/
3. Test in your workflow by trying different versions

## macOS Runners

### Available macOS Versions

**✅ Confirmed Available:**
- **macos-12** (Monterey) - Available
- **macos-13** (Ventura) - Available  
- **macos-14** (Sonoma) - ✅ Currently using this
- **macos-15** (Sequoia) - May be available (check GitHub Actions docs)

**Note:** GitHub Actions typically adds new macOS versions gradually. Check the [official documentation](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners#supported-runners-and-hardware-resources) for the latest.

### Current Configuration

Our workflow uses:
- **macOS Runner**: `macos-14` (Sonoma)
- **Swift Version**: `5.10`
- **swift-tools-version**: `5.10` (in Package.swift)
- **Build Platforms**: macOS 14, iOS 17 (in Package.swift)
- **Runtime Requirement**: macOS 15.0+, iOS 18.0+ (for Foundation Models)

## Compatibility Matrix

| Swift Version | macOS Runner | Status | Notes |
|--------------|--------------|--------|-------|
| 5.10 | macos-14 | ✅ Working | Current configuration |
| 5.10 | macos-13 | ✅ Should work | Older runner |
| 5.10 | macos-15 | ⚠️ Unknown | May not be available yet |
| **6.1.0** | **macos-14** | **✅ Available** | **Listed in swift-versions.ts** |
| 6.0.3 | macos-14 | ✅ Available | Listed in swift-versions.ts |
| 6.0 | macos-14 | ✅ Available | Listed in swift-versions.ts |
| 6.2 | macos-14 | ❌ Not available | Not in swift-versions.ts |

## Recommendations

### For Maximum Compatibility

1. **Swift Version**: Use **5.10** (proven to work)
2. **macOS Runner**: Use **macos-14** (widely available)
3. **swift-tools-version**: Match your Swift version (5.10)

### For Latest Features

1. **Swift Version**: Use **6.1.0** ✅ (confirmed available in swift-versions.ts)
2. **macOS Runner**: Use **macos-14** (confirmed) or **macos-15** (test needed)
3. **swift-tools-version**: Use **6.0** or **6.1** (compatible with Swift 6.1.0)

### Testing New Versions

To test a new Swift version:

```yaml
- name: Setup Swift
  uses: swift-actions/setup-swift@v1
  with:
    swift-version: "6.1.0"  # Try this version
```

If it fails, you'll get an error like:
```
Version "6.1.0" is not available
```

## Current Best Practice

Based on our experience:

**✅ Recommended Configuration:**
```yaml
runs-on: macos-14
steps:
  - uses: swift-actions/setup-swift@v1
    with:
      swift-version: "5.10"
```

**Package.swift:**
```swift
// swift-tools-version: 5.10
platforms: [
    .macOS(.v14),  // Build target
    .iOS(.v17)     // Build target
]
```

**Runtime Requirements:**
- Document that runtime requires macOS 15.0+ / iOS 18.0+ (if using Foundation Models)
- Use `@available(macOS 15.0, iOS 18.0, *)` for runtime-only features
- Use `#if canImport(FoundationModels)` for conditional compilation

## Future Considerations

1. **Swift 6.x**: As Swift 6.x becomes more stable, GitHub Actions will likely add support
2. **macOS 15**: As it becomes more widely available, consider migrating
3. **Foundation Models**: Requires macOS 15.0+ at runtime, but can build on macOS 14

## Resources

- [GitHub Actions macOS Runners](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners#supported-runners-and-hardware-resources)
- [Swift.org Downloads](https://swift.org/download/)
- [setup-swift Action](https://github.com/swift-actions/setup-swift)

---

**Last Updated**: Based on testing in November 2024  
**Current Working Config**: Swift 5.10 + macOS 14
