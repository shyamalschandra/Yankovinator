# Quick Start Guide

Yankovinator converts songs into theme-based parodies using Apple's NaturalLanguage framework and a local Ollama LLM (`llama3.2:3b` by default).

## Requirements

- Swift 5.10+ (Xcode recommended for running tests)
- macOS 13.0+
- [Ollama](https://ollama.ai) installed and running
- Model: `llama3.2:3b` (`ollama pull llama3.2:3b`)

## Install Ollama (macOS)

```bash
# GUI app (recommended)
brew install --cask ollama-app

# Or CLI
brew install ollama
ollama serve
```

Then pull the model:

```bash
ollama pull llama3.2:3b
ollama list
```

## Build and Verify

```bash
git clone https://github.com/shyamalschandra/Yankovinator.git
cd Yankovinator
swift build

swift run yankovinator --help
swift run keyword-generator --help
swift run benchmark --help
```

## Run Tests

XCTest requires the full Xcode toolchain (not Command Line Tools alone):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
```

Integration tests need Ollama running with `llama3.2:3b`.

## Usage Examples

### Generate keywords

```bash
swift run keyword-generator "artificial intelligence" --count 10 --output keywords.txt
```

### Generate a parody

```bash
swift run yankovinator data/example_lyrics.txt \
  --keywords data/example_keywords.txt \
  --output parody.txt \
  --verbose
```

### Benchmark performance

```bash
swift run benchmark \
  --lyrics data/example_lyrics.txt \
  --keywords data/example_keywords.txt \
  --iterations 5
```

### Parallel batch on cloud Ollama (10 workers)

```bash
mkdir -p songs out
cp data/example_lyrics.txt songs/a.txt
cp data/example_lyrics.txt songs/b.txt

swift run yankovinator --input-dir ./songs --output-dir ./out \
  --keywords data/example_keywords.txt \
  --ollama-url https://ollama.example.com \
  --workers 10 \
  --verbose
```

### Combinatorial batch (songs × themes × 10 candidates)

```bash
mkdir -p songs themes out
cp data/example_lyrics.txt songs/a.txt
cp data/example_lyrics.txt songs/b.txt
cp data/example_keywords.txt themes/space.txt

swift run yankovinator --input-dir ./songs --themes-dir ./themes \
  --output-dir ./out --workers 10 --candidates 10 --keep-candidates --verbose
```

Best outputs land at `out/<theme>/<song>.parody.txt`. Effective generations = `songs × themes × candidates`. Above 100, pass `--force`. Up to **10 consumers** run concurrently; cap aligns with **`OLLAMA_NUM_PARALLEL`** on local Ollama ([FAQ](https://docs.ollama.com/faq)).

### Certification battery (releases)

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./scripts/certification-battery.sh
```

## Tools

| Command | Purpose |
|---|---|
| `yankovinator` | Generate syllable-accurate parodies |
| `keyword-generator` | Create `keyword: definition` theme files via Ollama |
| `benchmark` | Measure generation performance |

## Unsupervised NLP (built in)

Generation now uses unlabeled NaturalLanguage signals by default:

- **Lexical substitution** — syllable-matched `NLEmbedding` neighbors
- **Rhyme clustering** — phonetic + embedding clusters for scheme detection
- **Coherence critic** — next-line surprise scoring (embedding + optional Ollama)

Disable with `ParodyGenerator(..., useUnsupervisedNLP: false)` if needed.

## Documentation

- [README.md](README.md) — full guide
- [docs/RELEASES.md](docs/RELEASES.md) — binary releases
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) — GitHub Pages
- Website: https://shyamalschandra.github.io/Yankovinator/

## Note on older migration docs

Some repository markdown files describe an unfinished Foundation Models migration. **The shipped product uses Ollama.** Prefer this guide and `README.md` for current instructions.
