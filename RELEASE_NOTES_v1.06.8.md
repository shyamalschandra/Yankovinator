# Yankovinator v1.06.8

## Certification battery expansion + docs / Pages / Homebrew

Expanded `./scripts/certification-battery.sh` into a full release gate:

- **Unit** — full `swift test`
- **Regression** — resume store, Rust TUI PATH, parallel jobs, fit scorer, concurrent NL, rhyme labels past `Z`
- **UX** — `--version` pin, help flag contracts
- **A/B** — Rust TUI env vs Swift fallback; `--no-progress` vs progress-enabled E2E
- **Blackbox** — TUI JSON protocol; fingerprint mismatch → `--fresh-batch`
- **E2E** — batch / candidates / cross-product / keyword-generator / benchmark / resume
- **Regression E2E** — `--fit-optimize --workers 4` (NL segfault class from v1.06.7)
- Writes `docs/certification-latest.txt` for GitHub Pages

Docs, README, Releases, and the Pages site are updated for **v1.06.8**.

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
yankovinator --version   # → 1.06.8
```

Or:

```bash
./scripts/install-local.sh ~/.local/bin
```

## Certify locally

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./scripts/certification-battery.sh
```

Guide: [docs/CERTIFICATION.md](docs/CERTIFICATION.md)
