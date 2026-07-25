# Yankovinator v1.04.4

## What's new

- **CLI fix:** `--ollama-num-workers` is a supported alias for `--ollama-num-parallel` (fixes mistaken batch runs that treated the flag value as a lyrics file)
- **Clearer validation** when batch mode picks up a stray numeric positional after an unknown long option

## Example (combinatorial batch)

```bash
yankovinator --input-dir ./yankovinator-songs --themes-dir ./yankovinator-themes \
  --output-dir ./output-songs --workers 10 --candidates 20 --keep-candidates --verbose \
  --model qwen3.5:397b-cloud --ollama-num-workers 10 --force
```

Add `--force` when songs×themes×candidates exceeds 100. For cloud models, consider `--ollama-timeout 600`.

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```

Universal: [v1.04.4 release](https://github.com/shyamalschandra/Yankovinator/releases/download/v1.04.4/yankovinator-universal.tar.gz)
