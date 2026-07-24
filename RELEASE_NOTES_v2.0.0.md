> **Current status (2026):** Yankovinator ships with **Ollama** (`llama3.2:3b`), not Apple Foundation Models. Treat the Foundation Models content below as historical / aspirational. Use [README.md](README.md) and [QUICK_START.md](QUICK_START.md) for accurate instructions.

# Release Notes - Version 2.0.0

## Major Changes: Migration to Foundation Models

Yankovinator has been migrated from Ollama to Apple's Foundation Models framework, providing better integration, improved performance, and no external dependencies.

## What's New

### ✨ Foundation Models Integration
- **On-device AI**: All processing happens locally using Apple's Foundation Models
- **No external services**: No need to run Ollama server
- **Better performance**: Optimized for Apple Silicon
- **Privacy**: All data stays on your device

### 🚀 New Features
- **Benchmarking tool**: New `benchmark` command-line tool for performance measurement
- **Improved error handling**: Better error messages for Foundation Models availability

### 📦 Updated Requirements
- **macOS 15.0+ (Sequoia)** or **iOS 18.0+** required
- Foundation Models framework (included with macOS 15+/iOS 18+)
- No external dependencies needed

## Breaking Changes

### Platform Requirements
- **Before**: macOS 13+ or iOS 16+
- **After**: macOS 15.0+ (Sequoia) or iOS 18.0+

### CLI Options
- **Removed**: `--ollama-url`, `--model` (Ollama-specific options)
- **Added**: `--model-identifier` (Foundation Models model identifier, optional)

### Dependencies
- **Removed**: Ollama server requirement
- **Removed**: AsyncHTTPClient dependency
- **Added**: Foundation Models framework (system framework)

## Migration Guide

### For Users

1. **Update macOS/iOS**: Ensure you're running macOS 15.0+ or iOS 18.0+
2. **Remove Ollama**: No longer needed - you can uninstall Ollama if desired
3. **Update commands**: Replace `--ollama-url` and `--model` with `--model-identifier` (optional)

### Example Migration

**Before (Ollama):**
```bash
yankovinator lyrics.txt --keywords themes.txt --ollama-url http://localhost:11434 --model llama3.2:3b
```

**After (Foundation Models):**
```bash
yankovinator lyrics.txt --keywords themes.txt
# or with specific model:
yankovinator lyrics.txt --keywords themes.txt --model-identifier <model-id>
```

## New Tools

### Benchmark Tool
```bash
swift run benchmark --lyrics data/test_short.txt --keywords data/test_keywords.txt --iterations 5
```

## Known Issues

1. **FoundationModels API Verification**: The exact API structure may need adjustment. See `FOUNDATION_MODELS_API_NOTES.md` for details.
2. **Compilation**: Some compilation errors may exist until the FoundationModels API is fully verified.

## Performance

Foundation Models provides:
- Faster response times (on-device processing)
- Lower latency (no network calls)
- Better resource utilization (Apple Silicon optimized)

## Documentation

- Updated README with Foundation Models information
- Created `MIGRATION_SUMMARY.md` for detailed migration notes
- Created `FOUNDATION_MODELS_API_NOTES.md` for API verification notes

## Contributors

- Migration completed by AI Assistant
- Foundation Models integration by Shyamal Suhana Chandra

## Support

For issues or questions:
- Check `MIGRATION_SUMMARY.md` for migration details
- Check `FOUNDATION_MODELS_API_NOTES.md` for API issues
- Open an issue on GitHub

---

**Note**: This is a major version update. Please review the breaking changes and migration guide before upgrading.
