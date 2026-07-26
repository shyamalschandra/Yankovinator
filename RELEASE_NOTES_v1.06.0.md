# Yankovinator v1.06.0

## What's new

**Breaking CLI simplification:** `yankovinator` is **batch-only**. Themes always come from **`--themes-dir`** (one `.txt` keyword file per theme).

### Removed

- Positional **lyrics file** argument
- **`--keywords` / `-k`** (shared theme file for all songs)
- **`--output` / `-o`** (single-file stdout/file output)

### Required flags

- **`--input-dir`** — directory of song `.txt` files
- **`--themes-dir`** — directory of theme keyword files (`keyword: definition` per line)
- **`--output-dir`** — writes **`out/<theme>/<song>.parody.txt`**

`benchmark` is unchanged (`--lyrics` + `--keywords`).

Includes all **v1.05.0** features (128 workers, `--consumers`, up to 64 candidates, cloud prescription, fit scoring, etc.).

## Example

```bash
mkdir -p songs themes out
cp data/example_lyrics.txt songs/twinkle.txt
cp data/example_keywords.txt themes/space.txt

yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \
  --workers 10 --candidates 10 --verbose
```

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```

Universal: [v1.06.0 release](https://github.com/shyamalschandra/Yankovinator/releases/download/v1.06.0/yankovinator-universal.tar.gz)
