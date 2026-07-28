# Yankovinator v1.06.9

## Ncurses-like TUI: color boxes + emoji bars per worker

`yankovinator-tui` (Rust/ratatui) now renders an alternate-screen dashboard with:

- **Overall** double-bordered cyan box + 🟩⬜ emoji batch progress
- **Feed** rounded magenta box for recent status lines
- **Per-thread worker boxes** — unique border colors, 🧵 W01… labels, ⚡/💤 state, and emoji progress bars (🟦🟩🟨🟪…) that track line progress when available, or pulse while waiting on Ollama
- Two-column worker grid on wide terminals; busy workers prioritized when height is short

JSON stdin protocol unchanged (Swift CLI drop-in).

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
# or:
./scripts/install-local.sh ~/.local/bin
yankovinator --version   # → 1.06.9
```
