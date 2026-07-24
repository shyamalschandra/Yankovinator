> **Current status (2026):** Yankovinator ships with **Ollama** (`llama3.2:3b`), not Apple Foundation Models. Use [README.md](README.md) and [QUICK_START.md](QUICK_START.md) for accurate instructions.

# Deployment Checklist (v1.04 / Ollama)

## Pre-release

- [x] Source builds: `swift build` / `swift build -c release`
- [x] XCTest suite green with Xcode developer dir (`swift test`)
- [x] CLI help works: `yankovinator`, `keyword-generator`, `benchmark`
- [x] Parallel workers verified (`--workers` / `--input-dir` batch)
- [x] Combinatorial songs×themes verified (`--themes-dir`)
- [x] Multi-candidate ranking verified (`--candidates 10`)
- [x] Ollama integration verified with `llama3.2:3b`
- [x] Sample data present: `data/example_lyrics.txt`, `data/example_keywords.txt`
- [x] Docs aligned with Ollama (README, QUICK_START, `docs/`)
- [x] GitHub Pages workflow present (`.github/workflows/pages.yml`)
- [x] Homebrew formula template present (`Formula/yankovinator.rb`)

## Release steps

```bash
git tag -a v1.04 -m "Release v1.04"
git push origin v1.04
```

After assets publish:

1. Verify release archives + `.sha256` files
2. Update Homebrew tap formula version + SHA256 (`./update-homebrew-tap.sh 1.04`)
3. Confirm Pages site: https://shyamalschandra.github.io/Yankovinator/

## Post-release smoke

```bash
yankovinator --help
keyword-generator --help
yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \
  --workers 10 --candidates 10 --keep-candidates --verbose
```

## Notes

- Effective generations = songs × themes × candidates
- Above 100 generations requires `--force`
- `--workers` caps total concurrent Ollama generations across the flattened expansion
