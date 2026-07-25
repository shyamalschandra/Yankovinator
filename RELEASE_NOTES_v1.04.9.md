# Yankovinator v1.04.9

## What's new

- **Word-by-word POS matching:** NaturalLanguage lexical classes aligned with syllable tokens; prompts require noun→noun, verb→verb, etc.
- **OED-aware suggestions:** Webster/OED lookups filtered by syllable count and part of speech; batch uses shared dictionary safely.
- **ParodyFitScorer:** Global ranking uses maximin-style score (65% weakest line + 35% mean) across syllables, POS, coherence, theme, and dictionary usage.
- **`--fit-optimize`:** Optional batch hill-climbing (extra Ollama) for higher fit; single-file mode runs full fit optimization by default.
- **Stability:** Serializes NaturalLanguage analysis across workers (fixes parallel batch crashes); fixes NL lock re-entrancy deadlock.

## Example

```bash
yankovinator --input-dir ./yankovinator-songs --themes-dir ./yankovinator-themes \
  --output-dir ./output-songs --workers 10 --candidates 20 --keep-candidates --verbose \
  --model deepseek-v4-pro:cloud --fit-optimize --force
```

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```

Universal: [v1.04.9 release](https://github.com/shyamalschandra/Yankovinator/releases/download/v1.04.9/yankovinator-universal.tar.gz)
