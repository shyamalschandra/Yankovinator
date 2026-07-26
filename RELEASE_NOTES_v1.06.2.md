# Yankovinator v1.06.2

## What's new

- **ncurses batch TUI (macOS):** interactive progress uses an **alternate screen** with in-place redraws — no scrolling worker dashboard while jobs run.
- **ANSI fallback:** non-TTY / CI / `--no-progress` unchanged; improved cursor-up fallback when ncurses is unavailable.

Includes **v1.06.1** (parallel NL + MIDI crash fixes) and **v1.06.0** (batch-only CLI).

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```

Universal: [v1.06.2 release](https://github.com/shyamalschandra/Yankovinator/releases/download/v1.06.2/yankovinator-universal.tar.gz)
