# Yankovinator v1.06.13

## License-driven concurrency cap (max 10)

Concurrent Ollama/generation consumers are hard-capped at **10** for all modes (local and cloud), per license terms:

- `--workers` / `--jobs`, `--consumers`, and `--ollama-num-parallel` never yield more than **10** in-flight generations
- Requests above 10 are **clamped** with a clear stderr warning (e.g. `--workers 20` → 10)
- Cloud prescription soft default remains **4** for `:cloud` rate limits; `--no-cloud-prescription` may raise concurrency up to the license max of **10** (not 128)

## Install

```bash
./scripts/install-local.sh ~/.local/bin
# or after release:
brew upgrade shyamalschandra/yankovinator/yankovinator
yankovinator --version   # → 1.06.13
```

## Example clamp

```bash
yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \
  --workers 20 --candidates 1 --verbose
# stderr: License terms limit … Capping --workers 20→10
```
