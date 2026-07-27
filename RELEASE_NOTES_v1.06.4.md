# Yankovinator v1.06.4

## Batch resume checkpointing

- Durable progress under `<output-dir>/.yankovinator/` (`manifest.json`, `completed.jsonl`, per-candidate artifacts).
- Re-run the same batch command after interrupt to skip finished song×theme×candidate units.
- **`--fresh-batch`** wipes the checkpoint and regenerates everything.
- Manifest fingerprint mismatches (songs, themes, model, `--candidates`) prompt a clear error.

## Rust batch TUI (UX fix)

- New **`yankovinator-tui`** sidecar (Rust + ratatui/crossterm): UTF-8 emoji, colors, and worker gauges on stderr without Swift alternate-screen races.
- Auto-launched when the binary sits beside `yankovinator` (included in release tarballs).
- **`YANKOVINATOR_RUST_TUI=0`** forces Swift fallback; **`YANKOVINATOR_TUI_PATH`** overrides the binary path.
- Stderr **`StderrGate`** avoids interleaved logs corrupting the dashboard.

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
# Install yankovinator-tui next to yankovinator from the universal tarball.
```

Universal: [v1.06.4 release](https://github.com/shyamalschandra/Yankovinator/releases/download/v1.06.4/yankovinator-universal.tar.gz)
