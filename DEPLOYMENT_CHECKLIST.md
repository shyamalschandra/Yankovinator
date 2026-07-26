> **Current status (2026):** Yankovinator ships with **Ollama** (`llama3.2:3b`), not Apple Foundation Models. Use [README.md](README.md) and [QUICK_START.md](QUICK_START.md) for accurate instructions.

# Deployment Checklist (v1.05.0 / Ollama)

## Pre-release

- [x] Source builds: `swift build` / `swift build -c release`
- [x] XCTest suite green with Xcode developer dir (`swift test`)
- [x] Certification battery: `./scripts/certification-battery.sh`
- [x] Parallel workers up to **128**; `--consumers`; HTTP pool scaling
- [x] Word-by-word POS + ParodyFitScorer + `--fit-optimize`
- [x] Ollama `think: false` on generate (thinking models)
- [x] Docs aligned (README, `docs/RELEASES.md`, GitHub Pages workflow)

## Release steps

```bash
git tag -a v1.05.0 -m "Release v1.05.0"
git push origin v1.05.0
```

After assets publish:

1. Verify release archives + `.sha256` files
2. Update Homebrew tap (`./update-homebrew-tap.sh 1.05.0`)
3. Confirm Pages: https://shyamalschandra.github.io/Yankovinator/

## Post-release smoke

```bash
yankovinator --help
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```
