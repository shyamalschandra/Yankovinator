# Yankovinator v1.04.3

## What's new

- **Faster batch startup:** shared OED dictionary, one-time model verify, preloaded lyrics/themes, no per-job keyword parser init
- **TUI:** async coalesced redraws, status rail + message feed, per-worker ⏱ spent / ⌛ ETA, batch timing on overall line
- **`OLLAMA_NUM_PARALLEL`:** aligns consumer pool with Ollama server parallelism ([docs.ollama.com/faq](https://docs.ollama.com/faq)); `--ollama-num-parallel` and `$OLLAMA_NUM_PARALLEL` on localhost

## Local Ollama parallelism

```bash
export OLLAMA_NUM_PARALLEL=10
ollama serve
```

```bash
yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \
  --workers 10 --candidates 10 --ollama-num-parallel 10
```

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```

Universal: [v1.04.3 release](https://github.com/shyamalschandra/Yankovinator/releases/download/v1.04.3/yankovinator-universal.tar.gz)
