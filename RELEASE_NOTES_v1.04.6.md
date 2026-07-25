# Yankovinator v1.04.6

## What's new

- **Cloud batch prescription** for heavy `:cloud` models (e.g. `qwen3.5:397b-cloud`): auto cap at **4** consumers, **600s** timeout, skip extra LLM coherence probes per line
- **Per-worker line progress** in the TUI (`L12/48` on each worker row while a song generates)
- **`--no-cloud-prescription`** to keep full `--workers` against cloud models

## Example

```bash
yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \
  --workers 10 --candidates 20 --model qwen3.5:397b-cloud --ollama-num-workers 10 --force --verbose
```

Prescription lines print on stderr before the TUI starts.

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```

Universal: [v1.04.6 release](https://github.com/shyamalschandra/Yankovinator/releases/download/v1.04.6/yankovinator-universal.tar.gz)
