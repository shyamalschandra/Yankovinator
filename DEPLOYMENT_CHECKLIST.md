> **Current status (2026):** Yankovinator ships with **Ollama** (`llama3.2:3b`), not Apple Foundation Models. Use [README.md](README.md) and [QUICK_START.md](QUICK_START.md) for accurate instructions.

# Deployment Checklist (v1.04.7 / Ollama)

## Pre-release

- [x] Source builds: `swift build` / `swift build -c release`
- [x] XCTest suite green with Xcode developer dir (`swift test`)
- [x] Certification battery: `./scripts/certification-battery.sh`
- [x] CLI help works: `yankovinator`, `keyword-generator`, `benchmark`
- [x] OLLAMA_NUM_PARALLEL alignment + `--ollama-num-parallel` / `--ollama-num-workers`
- [x] `--midi-progress` MIDI cues per worker bar (macOS, interactive)
- [x] Cloud batch prescription + `--no-cloud-prescription`
- [x] Batch fast path + incremental `.parody.txt` checkpoints
- [x] Batch startup optimizations + async TUI with worker ETAs
- [x] Cloud Ollama retries / `--ollama-timeout`
- [x] Combinatorial songs×themes×candidates verified
- [x] Ollama integration verified with `llama3.2:3b`
- [x] Sample data present: `data/example_lyrics.txt`, `data/example_keywords.txt`
- [x] Docs aligned with Ollama (README, QUICK_START, `docs/`)
- [x] GitHub Pages workflow present (`.github/workflows/pages.yml`)
- [x] Homebrew formula template present (`Formula/yankovinator.rb`)

## Release steps

```bash
git tag -a v1.04.7 -m "Release v1.04.7"
git push origin v1.04.7
```

After assets publish:

1. Verify release archives + `.sha256` files
2. Update Homebrew tap formula version + SHA256 (`./update-homebrew-tap.sh 1.04.7`)
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
- `--workers` requests parallelism; at most **10 consumer workers** run at once (producer–consumer queue)
