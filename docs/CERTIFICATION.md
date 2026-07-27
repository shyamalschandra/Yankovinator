# Certification battery

Release and main-branch verification runs:

```bash
./scripts/certification-battery.sh
```

## What it covers

| Phase | Type | Checks |
|-------|------|--------|
| 1 | Build | `swift build` debug + release |
| 2 | Unit / regression | Full `swift test` (73+ tests) |
| 3 | CLI | `--help` for all executables |
| 4 | Help / UX | New flags (`fresh-batch`, `fit-optimize`, TUI-related docs in help) |
| 4b–c | Blackbox | `cargo build` + `yankovinator-tui` stdin JSON protocol |
| 4d | Unit | `BatchResumeStoreTests` |
| 4e | A/B env | `YANKOVINATOR_RUST_TUI` opt-out |
| 5 | Validation | Invalid `--workers`, `--candidates`, bad paths |
| 6 | Site | `npm run build` (GitHub Pages TS bundle) |
| 7–14 | E2E (Ollama) | Batch, candidates, cross-product, keyword-generator, benchmark, resume + `--fresh-batch` |

E2E sections require a local Ollama on `http://localhost:11434` with a usable model (default `llama3.2:3b`).

## Known certification gap (fixed in v1.06.6)

E2E historically used **`--no-progress`**, so the interactive multi-worker TUI was **not** load-tested. That left a segfault when:

1. `yankovinator` was invoked as a **bare PATH name** (argv0 without directory), so sibling `yankovinator-tui` was not found.
2. Swift fell back to **multiline cursor-up** redraws (+ optional MIDI) under 10 workers → terminal corruption / segfault.

**v1.06.6** resolves PATH for the TUI sidecar and never uses multiline Swift redraw for worker pools (single-line or Rust TUI only).

## Environment

- `DEVELOPER_DIR` — Xcode app path for XCTest (default: `/Applications/Xcode.app/Contents/Developer`)
- `YANKOVINATOR_RUST_TUI=0` — certification still verifies opt-out semantics in section 4e

Exit code **0** only when all executed checks pass.
