# Yankovinator v1.06.3

## Bug fixes

Fixes **garbled batch TUI** (`~V~Q` mojibake) and **`segmentation fault`** during parallel runs introduced in v1.06.2.

- **Removed ncurses** for the worker dashboard (it stripped ANSI/color/emoji and mishandled UTF-8 box drawing).
- **ANSI alternate screen** instead: same Unicode bars, colors, and emojis as before, redrawn in-place without scrollback growth.
- **Serialized stderr TUI** writes on one queue to avoid terminal corruption.

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```

Universal: [v1.06.3 release](https://github.com/shyamalschandra/Yankovinator/releases/download/v1.06.3/yankovinator-universal.tar.gz)
