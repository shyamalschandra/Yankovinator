# Yankovinator v1.06.11

## Cloud batch resilience (429 / 502 / port exhaustion)

High-parallel runs against Ollama **`:cloud`** models (e.g. `gemma4:31b-cloud`) no longer abort the whole batch on the first rate-limit or gateway blip:

- **Retries** on HTTP **429 / 502 / 503 / 504** and transient network errors (including `can't assign requested address`) with exponential backoff + jitter
- Honors **`Retry-After`** when present
- Shared HTTP client keeps connections warmer; cloud runs gate in-flight HTTP calls to the consumer pool
- Cloud prescription now applies to **all** `:cloud` models (not only huge qwen/397b): default consumer cap **4** (use `--no-cloud-prescription` to raise)
- Verbose “Detected rhyme scheme…” prints once per scheme (serialized) instead of once per parallel job

Local Ollama stays uncapped by cloud prescription and uses fewer retries / higher connection limits.

## Install

```bash
./scripts/install-local.sh ~/.local/bin
# or after release:
brew upgrade shyamalschandra/yankovinator/yankovinator
yankovinator --version   # → 1.06.11
```

## Recommended cloud re-run

```bash
yankovinator --input-dir ./yankovinator-songs --themes-dir ./yankovinator-themes \
  --output-dir ./output-songs --workers 4 --candidates 20 --keep-candidates --verbose \
  --model gemma4:31b-cloud --force --fresh-batch
```

If a prior run left a contaminated checkpoint under `output-songs/.yankovinator`, **`--fresh-batch`** is required (or use a new `--output-dir`).
