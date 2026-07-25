# Yankovinator v1.04.1

## What's new

- **Producer–consumer job queue:** batch and multi-candidate runs use a bounded worker pool (at most **10 consumers** at once), even if `--workers` is higher
- **Progress bar:** stderr progress for multi-generation runs (`Generations [=====> ] n/total`); disable with `--no-progress`
- **Cloud Ollama resilience:** longer default timeouts for `:cloud` models, HTTP retries with backoff, `--ollama-timeout` (30–900s)
- **`scripts/certification-battery.sh`:** full release certification (build, XCTest, CLI, E2E)

## Install

### Homebrew

```bash
brew tap shyamalschandra/yankovinator
brew update
brew upgrade yankovinator
```

### Universal binary

```bash
curl -L -o yankovinator-universal.tar.gz \
  https://github.com/shyamalschandra/Yankovinator/releases/download/v1.04.1/yankovinator-universal.tar.gz
tar -xzf yankovinator-universal.tar.gz
sudo mv yankovinator keyword-generator benchmark /usr/local/bin/
```

## Heavy cloud batch (stable concurrency)

```bash
yankovinator --input-dir ./songs --themes-dir ./themes \
  --output-dir ./out \
  --workers 10 \
  --candidates 20 \
  --model gemma4:cloud \
  --ollama-timeout 600 \
  --keep-candidates
# Progress bar on stderr; add --verbose for per-job logs or --no-progress for quiet
```
