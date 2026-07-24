> **Current status (2026):** Yankovinator ships with **Ollama** (`llama3.2:3b`), not Apple Foundation Models. Use [README.md](README.md) and [QUICK_START.md](QUICK_START.md) for accurate instructions.

# Deployment Checklist (v1.03 / Ollama)

## Pre-release

- [x] Source builds: `swift build` / `swift build -c release`
- [x] XCTest suite green with Xcode developer dir (`swift test`)
- [x] CLI help works: `yankovinator`, `keyword-generator`, `benchmark`
- [x] Parallel workers verified (`--workers` / `--input-dir` batch)
- [x] Ollama integration verified with `llama3.2:3b`
- [x] Sample data present: `data/example_lyrics.txt`, `data/example_keywords.txt`
- [x] Docs aligned with Ollama (README, QUICK_START, `docs/`)
- [x] GitHub Pages workflow present (`.github/workflows/pages.yml`)
- [x] Homebrew formula template present (`Formula/yankovinator.rb`)

## Release steps

```bash
# Tag and push (example)
git tag -a v1.03 -m "Release v1.03"
git push origin v1.03

# Or dispatch Build and Release workflow with version tag
```

After assets publish:

1. Verify release archives + `.sha256` files
2. Update Homebrew tap formula version + SHA256 (`./update-homebrew-tap.sh 1.03`)
3. Confirm Pages site: https://shyamalschandra.github.io/Yankovinator/

## Post-release smoke

```bash
yankovinator --help
keyword-generator --help
curl http://localhost:11434/api/tags
yankovinator data/example_lyrics.txt --keywords data/example_keywords.txt
yankovinator --input-dir ./songs --output-dir ./out --workers 10 --verbose
```

## Notes

- Runtime requires Ollama (local or cloud via `--ollama-url`) + model pull
- `swift test` requires full Xcode (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`)
- Dist binaries labeled `arm64`/`universal` should be verified with `file` / `lipo` before publishing
