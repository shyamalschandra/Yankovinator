> **Current status (2026):** Yankovinator ships with **Ollama** (`llama3.2:3b`), not Apple Foundation Models. Use [README.md](README.md) and [QUICK_START.md](QUICK_START.md) for accurate instructions.

# Deployment Checklist (v1.06.8 / Ollama)

## Pre-release

- [ ] Source builds: `swift build` / `swift build -c release`
- [ ] XCTest suite green with Xcode developer dir (`swift test`)
- [ ] Certification battery: `./scripts/certification-battery.sh` (unit, regression, UX, A/B, blackbox, E2E, fit-optimize)
- [ ] Report committed: `docs/certification-latest.txt`
- [ ] Docs aligned (README, `docs/CERTIFICATION.md`, `docs/RELEASES.md`, Pages workflow)
- [ ] `RELEASE_NOTES_v1.06.8.md` ready

## Release steps

```bash
./scripts/certification-battery.sh
git tag -a v1.06.8 -m "Release v1.06.8"
git push origin main
git push origin v1.06.8
```

After assets publish:

1. Verify release archives + `.sha256` files
2. Update Homebrew tap (`./update-homebrew-tap.sh 1.06.8`)
3. Confirm Pages: https://shyamalschandra.github.io/Yankovinator/
4. Confirm certification docs: https://shyamalschandra.github.io/Yankovinator/CERTIFICATION.md

## Post-release smoke

```bash
yankovinator --version   # → 1.06.8
yankovinator --help
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```
