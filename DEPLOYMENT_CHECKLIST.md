> **Current status (2026):** Yankovinator ships with **Ollama** (`llama3.2:3b`), not Apple Foundation Models. Use [README.md](README.md) and [QUICK_START.md](QUICK_START.md) for accurate instructions.

# Deployment Checklist (v1.02 / Ollama)

## Pre-release

- [x] Source builds: `swift build` / `swift build -c release`
- [x] XCTest suite green with Xcode developer dir (`swift test`)
- [x] CLI help works: `yankovinator`, `keyword-generator`, `benchmark`
- [x] Ollama integration verified with `llama3.2:3b`
- [x] Sample data present: `data/example_lyrics.txt`, `data/example_keywords.txt`
- [x] Docs aligned with Ollama (README, QUICK_START, `docs/`)
- [x] GitHub Pages workflow present (`.github/workflows/pages.yml`)
- [x] Homebrew formula template present (`Formula/yankovinator.rb`)

## Release steps

```bash
# Tag and push (example)
git tag -a v1.02 -m "Release v1.02"
git push origin v1.02

# Or dispatch Build and Release workflow with version tag
```

After assets publish:

1. Verify release archives + `.sha256` files
2. Update Homebrew tap formula version + SHA256
3. Confirm Pages site: https://shyamalschandra.github.io/Yankovinator/

## Post-release smoke

```bash
yankovinator --help
keyword-generator --help
curl http://localhost:11434/api/tags
yankovinator data/example_lyrics.txt --keywords data/example_keywords.txt
```

## Notes

- Runtime requires local Ollama + model pull
- `swift test` requires full Xcode (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`)
- Dist binaries labeled `arm64`/`universal` should be verified with `file` / `lipo` before publishing
