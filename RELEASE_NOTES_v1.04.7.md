# Yankovinator v1.04.7

## What's new

- **Batch fast path:** one `/api/generate` per lyric line (refinement and coherence re-gen off in batch)
- **Slim batch prompts:** no OED download or unsupervised NLP bloat on each line
- **Incremental checkpoints:** best `.parody.txt` written after each candidate finishes (not only at the end)
- **Bug fix:** `refinementPasses: 0` in batch no longer crashes (`1...0` range trap)
- **Cloud prescription** messaging clarified (worker cap limits parallel HTTP jobs, not model speed)

## Example

```bash
yankovinator --input-dir ./yankovinator-songs --themes-dir ./yankovinator-themes \
  --output-dir ./output-songs --workers 10 --candidates 20 --keep-candidates --verbose \
  --model qwen3.5:397b-cloud --ollama-num-workers 10 --force
```

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```

Universal: [v1.04.7 release](https://github.com/shyamalschandra/Yankovinator/releases/download/v1.04.7/yankovinator-universal.tar.gz)
