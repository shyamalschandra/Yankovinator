# Yankovinator v1.04.8

## What's new

- **Thinking models (Ollama):** all `/api/generate` calls send `think: false` so models like **deepseek-v4-pro:cloud** return lyric text in `response` instead of empty lines with content only in `thinking`
- **Empty-line guard:** rejects empty model output with a clear error instead of writing blank `.parody.txt` files and `score=0.000`
- **Tests:** `OllamaGenerateResponseTests` for request body and response parsing

## Example

```bash
yankovinator --input-dir ./yankovinator-songs --themes-dir ./yankovinator-themes \
  --output-dir ./output-songs --workers 10 --candidates 20 --keep-candidates --verbose \
  --model deepseek-v4-pro:cloud --ollama-num-workers 10 --force
```

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```

Universal: [v1.04.8 release](https://github.com/shyamalschandra/Yankovinator/releases/download/v1.04.8/yankovinator-universal.tar.gz)
