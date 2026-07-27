# Yankovinator v1.06.7

## Bug fix: segfault during `--fit-optimize` batch

**Cause:** With `--workers 10 --fit-optimize -v`, parallel workers raced on Apple NaturalLanguage:

- `ParodyFitScorer` called `analyzeWordSyllablesUnsafe` **without** the NL lock
- Each `ParodyGenerator` init loaded `NLEmbedding` (even when unsupervised NLP was off for batch)
- Static `CoherenceCritic` embedding queries were not serialized
- Rhyme labels past `Z` overflowed into `[\\]^_\`` (cosmetic; fixed)

**Fix:**

- Shared process-wide embeddings (`SharedNLEmbeddings`) under a **recursive** NL lock
- Safe syllable APIs in fit scoring; batch skips unused embedding engines
- Serialize verbose `print` from workers
- Warm embeddings once before the worker pool starts

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
yankovinator --version   # → 1.06.7
```

For a mismatched checkpoint in `--output-dir`:

```bash
yankovinator ... --fresh-batch
```
