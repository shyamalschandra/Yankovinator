# Yankovinator v1.05.0

## What's new

- **Massive batch parallelism:** up to **128** `--workers` and **128** concurrent consumers (was capped at 10)
- **`--consumers N`:** optional cap on in-flight jobs separate from queue depth
- **Heavy cloud prescription:** worker cap raised to **64** (use `--no-cloud-prescription` for full `--workers`)
- **HTTP pool:** scales to **512** connections per host when worker count is high
- **`--candidates`:** up to **64** ranked variants per song×theme

Includes all **v1.04.9** features: POS-aware prompts, OED suggestions, ParodyFitScorer, `--fit-optimize`, `think: false` for Ollama thinking models.

## Example

```bash
yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \
  --workers 64 --consumers 64 --candidates 20 --fit-optimize \
  --model deepseek-v4-pro:cloud --ollama-num-workers 64 --no-cloud-prescription --force
```

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```

Universal: [v1.05.0 release](https://github.com/shyamalschandra/Yankovinator/releases/download/v1.05.0/yankovinator-universal.tar.gz)
