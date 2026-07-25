# Yankovinator v1.04.2

## What's new

- **TUI progress** on stderr for batch / multi-candidate runs: Unicode block bars (`░▏▌█`), box-drawing frame, ANSI colors, emojis (☁️ 📊 ⚡ 💤 ✅)
- **Per cloud worker** rows (W01–W10) with animated pulses while each Ollama job runs
- Plain ASCII progress when stderr is not a TTY (CI, pipes); `--no-progress` still disables the UI

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```

Or download [v1.04.2 universal](https://github.com/shyamalschandra/Yankovinator/releases/download/v1.04.2/yankovinator-universal.tar.gz).

## Example

```bash
yankovinator --input-dir ./songs --themes-dir ./themes \
  --output-dir ./out --workers 10 --candidates 10 --model gemma4:cloud
```
