# Yankovinator v1.02

## Highlights

- **Unsupervised NLP helpers** for parody generation:
  - Embedding-based lexical substitution (syllable-matched)
  - Phonetic + embedding rhyme clustering
  - Next-line coherence / surprise critic (embedding + optional Ollama)
- **OED / Webster dictionary suggestions** for richer word choice
- **Docs + GitHub Pages** refreshed for the current Ollama-based product
- Sample inputs: `data/example_lyrics.txt`, `data/example_keywords.txt`
- CLI tools: `yankovinator`, `keyword-generator`, `benchmark`

## Requirements

- macOS 13.0+
- Ollama running locally with `llama3.2:3b` (`ollama pull llama3.2:3b`)

## Install

### Homebrew

```bash
brew tap shyamalschandra/yankovinator
brew install yankovinator
```

### Universal binary

```bash
curl -L -o yankovinator-universal.tar.gz \
  https://github.com/shyamalschandra/Yankovinator/releases/download/v1.02/yankovinator-universal.tar.gz
tar -xzf yankovinator-universal.tar.gz
sudo mv yankovinator keyword-generator /usr/local/bin/
[ -f benchmark ] && sudo mv benchmark /usr/local/bin/
```

## Quick test

```bash
yankovinator --help
keyword-generator --help
yankovinator data/example_lyrics.txt --keywords data/example_keywords.txt --verbose
```

## Notes

- Unsupervised NLP is enabled by default; disable with `ParodyGenerator(..., useUnsupervisedNLP: false)`.
- `swift test` requires full Xcode (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).
