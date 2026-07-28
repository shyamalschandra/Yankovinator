# Yankovinator v1.06.10

## Per-worker elapsed + remaining on every progress bar

Each worker progress bar now shows **elapsed** and **remain** inline:

- Working workers: elapsed = current job time; remain uses line-progress ETA when available, otherwise recent job averages
- Idle workers: elapsed = cumulative busy time; remain = estimated share of remaining queue
- Overall batch bar also labels `elapsed` / `remain`
- Rust TUI color boxes place timing on the emoji bar row itself

## Install

```bash
./scripts/install-local.sh ~/.local/bin
# or after release:
brew upgrade shyamalschandra/yankovinator/yankovinator
yankovinator --version   # → 1.06.10
```
