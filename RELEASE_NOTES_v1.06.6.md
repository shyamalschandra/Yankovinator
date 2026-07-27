# Yankovinator v1.06.6

## Bug fix: multi-worker segfault

**Cause:** Invoking `yankovinator` as a bare PATH name (no directory in argv0) failed to find sibling `yankovinator-tui`. The CLI fell back to Swift **multiline** stderr redraws (and MIDI), which corrupted the terminal and **segfaulted** under 10 workers.

**Why certification missed it:** E2E used `--no-progress`, so the interactive worker dashboard was never load-tested.

## Fixes

- Resolve `yankovinator-tui` via **PATH** and absolute CLI path (not only argv0 sibling).
- Worker-pool progress: **Rust TUI** or **single-line** `\r` only — never Swift multiline cursor-up.
- MIDI only when Rust TUI is active.
- Unit tests for TUI path override; certification notes + PATH check.

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
# or: ./scripts/install-local.sh ~/.local/bin
yankovinator --version   # → 1.06.6
```
