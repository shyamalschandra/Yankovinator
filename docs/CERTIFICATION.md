# Certification battery

Release and main-branch verification for Yankovinator. Run before tagging a release:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./scripts/certification-battery.sh
```

The script writes a machine-readable summary to [`certification-latest.txt`](certification-latest.txt) (published on GitHub Pages).

**Expect version:** `1.06.14` (override with `YANKOVINATOR_EXPECT_VERSION`).

## Coverage matrix

| Phase | Type | Checks |
|-------|------|--------|
| 1 | Build | `swift build` debug + release |
| 2 | Unit | Full `swift test` suite |
| 3 | CLI / UX | `--help` for `yankovinator`, `keyword-generator`, `benchmark` |
| 4 | UX | `--version` pin; help flags (`fresh-batch`, `fit-optimize`, `midi-progress`, …) |
| 4b–c | Blackbox | `cargo build` + `yankovinator-tui` stdin JSON protocol |
| 4d | Regression | Filtered XCTest: resume, Rust TUI path, parallel jobs, fit scorer, cloud plan, candidates; concurrent NL + rhyme labels |
| 4e | A/B | `YANKOVINATOR_RUST_TUI` default vs `=0`; PATH discovery; `YANKOVINATOR_TUI_PATH` |
| 5 | Blackbox | Invalid workers/candidates/paths; **fingerprint mismatch → `--fresh-batch`** |
| 6 | Site | `npm run build` (GitHub Pages TypeScript) |
| 7 | Probe | Ollama HTTP on `localhost:11434` |
| 8–14 | E2E | Batch, candidates, cross-product, keyword-generator, benchmark, resume + `--fresh-batch` |
| 15 | Regression E2E | **`--fit-optimize --workers 4`** (NaturalLanguage segfault class) |
| 16 | UX A/B E2E | `--no-progress` vs progress-enabled (Swift single-line when Rust TUI off) |

E2E sections (7+) require a local Ollama with a usable model (default `llama3.2:3b`). If Ollama is down, those phases are marked fail and earlier phases still report.

## Historical gaps (closed)

| Release | Gap | Fix |
|---------|-----|-----|
| ≤1.06.5 | E2E used `--no-progress` only → interactive TUI / PATH argv0 segfault missed | v1.06.6 PATH resolve + no Swift multiline worker TUI |
| ≤1.06.6 | Parallel `--fit-optimize` raced on NaturalLanguage / embeddings | v1.06.7 shared embeddings + safe fit scoring |
| 1.06.8 | Certification battery now load-tests fit-optimize + progress A/B | This document + sections 15–16 |

## Environment

| Variable | Role |
|----------|------|
| `DEVELOPER_DIR` | Xcode path for XCTest (default: `/Applications/Xcode.app/Contents/Developer`) |
| `YANKOVINATOR_RUST_TUI=0` | Force Swift progress path (still certified in 4e / 16) |
| `YANKOVINATOR_TUI_PATH` | Explicit `yankovinator-tui` binary |
| `YANKOVINATOR_EXPECT_VERSION` | Version string asserted in phase 4 (default `1.06.14`) |
| `YANKOVINATOR_CERT_REPORT` | Report path (default `docs/certification-latest.txt`) |

Exit code **0** only when every executed check passes.
