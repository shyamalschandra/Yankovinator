> **Current status (2026):** Yankovinator ships with **Ollama** (`llama3.2:3b`), not Apple Foundation Models. Use [README.md](README.md) and [QUICK_START.md](QUICK_START.md) for accurate instructions.

# Deployment Checklist (v1.04.9 / Ollama)

## Pre-release

- [x] Source builds: `swift build` / `swift build -c release`
- [x] XCTest suite green with Xcode developer dir (`swift test`)
- [x] Certification battery: `./scripts/certification-battery.sh`
- [x] CLI help works: `yankovinator`, `keyword-generator`, `benchmark`
- [x] Word-by-word POS + ParodyFitScorer global ranking
- [x] `--fit-optimize` batch hill-climbing (optional)
- [x] NLConcurrency lock (parallel batch safe)
- [x] Ollama `think: false` on generate (thinking models e.g. deepseek-v4-pro:cloud)
- [x] Combinatorial songs×themes×candidates verified
- [x] Ollama integration verified with `llama3.2:3b`
- [x] Sample data present: `data/example_lyrics.txt`, `data/example_keywords.txt`
- [x] Docs aligned with Ollama (README, QUICK_START, `docs/`)
- [x] GitHub Pages workflow present (`.github/workflows/pages.yml`)
- [x] Homebrew formula template present (`Formula/yankovinator.rb`)

## Release steps

```bash
git tag -a v1.04.9 -m "Release v1.04.9"
git push origin v1.04.9
```

After assets publish:

1. Verify release archives + `.sha256` files
2. Update Homebrew tap formula version + SHA256 (`./update-homebrew-tap.sh 1.04.9`)
3. Confirm Pages site: https://shyamalschandra.github.io/Yankovinator/

## Post-release smoke

```bash
yankovinator --help
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```
