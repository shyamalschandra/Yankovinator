# Yankovinator v1.06.12

## Disk-paged batch checkpoints

Batch resume under `--output-dir/.yankovinator/` no longer keeps an all-or-nothing in-memory copy of every completed candidate:

- **Incremental durability:** each finished song×theme×candidate writes its artifact, then appends + fsyncs `completed.jsonl` (crash-safe partial progress)
- **Paged resume:** opening a checkpoint streams the JSONL for keys/scores only; candidate texts stay on disk until needed
- **Bounded LRU:** full parody texts are cached with a small page limit (default 16); ranking uses on-disk scores and lazy-loads winners
- **`--keep-candidates`:** ranked bundles are copied from checkpoint artifacts without buffering every text at once
- Unchanged: `--fresh-batch`, fingerprint mismatch → re-run with `--fresh-batch` or a new `--output-dir`

## Install

```bash
./scripts/install-local.sh ~/.local/bin
# or after release:
brew upgrade shyamalschandra/yankovinator/yankovinator
yankovinator --version   # → 1.06.12
```

## Verify with a large `--candidates` batch

```bash
# Start a long run, interrupt mid-way, then resume — RAM should stay flat while
# .yankovinator/completed.jsonl and candidates/ grow as units finish.
yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \
  --candidates 32 --workers 4 --force --verbose

# Ctrl+C, then re-run the same command (no --fresh-batch) to skip finished units.
# Inspect checkpoint size vs process RSS; ranking still picks best from on-disk scores.
ls -la out/.yankovinator/completed.jsonl out/.yankovinator/candidates/
```
