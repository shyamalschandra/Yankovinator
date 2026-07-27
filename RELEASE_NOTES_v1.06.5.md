# Yankovinator v1.06.5

## Why this release

Homebrew / GitHub **v1.06.3** still segfaulted (or silently exited) on multi-worker batches with `--midi-progress`. **v1.06.5** ships the fixes plus resume checkpointing and the Rust batch TUI.

## Fixes

- **No Swift alternate-screen** for multi-worker pools (segfault with MIDI + parallel redraw).
- **MIDI prewarm** before the progress UI starts; pulse cues capped when workers &gt; 6.
- **OED wait** before parallel generation; safer checkpoint errors.
- Lazy spawn of **`yankovinator-tui`** (ratatui) after MIDI prewarm.
- CLI **`--version`** reports `1.06.5`; use `scripts/install-local.sh` to overwrite a stale Homebrew binary.

## Features (since v1.06.3)

- Batch **resume** under `<output-dir>/.yankovinator/` + **`--fresh-batch`**.
- Release archives include **`yankovinator-tui`** next to `yankovinator`.

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
# Ensure yankovinator-tui is installed beside yankovinator (universal tarball).
yankovinator --version   # → 1.06.5
```

Universal: [v1.06.5 release](https://github.com/shyamalschandra/Yankovinator/releases/download/v1.06.5/yankovinator-universal.tar.gz)
