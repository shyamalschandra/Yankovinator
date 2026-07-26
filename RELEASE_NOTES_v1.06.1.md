# Yankovinator v1.06.1

## Bug fixes

Fixes **`zsh: trace trap`** crashes during parallel batch runs (especially with **`--jobs 10`**, **`--fit-optimize`**, and **`--midi-progress`**).

- **NaturalLanguage:** Global lock now covers rhyme detection, parody tokenization/capitalization, and syllable counting so multiple workers do not touch `NLTokenizer` concurrently.
- **`--midi-progress`:** All `AVAudioEngine` / sampler I/O runs on the main actor; safer shutdown when notes overlap.
- **Worker TUI:** Skips redundant line-progress redraws when line/total unchanged.

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```

Universal: [v1.06.1 release](https://github.com/shyamalschandra/Yankovinator/releases/download/v1.06.1/yankovinator-universal.tar.gz)
