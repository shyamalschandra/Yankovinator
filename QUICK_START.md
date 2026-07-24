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

## Tools

| Command | Purpose |
|---|---|
| `yankovinator` | Generate syllable-accurate parodies |
| `keyword-generator` | Create `keyword: definition` theme files via Ollama |
| `benchmark` | Measure generation performance |

## Documentation

- [README.md](README.md) — full guide
- [docs/RELEASES.md](docs/RELEASES.md) — binary releases
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) — GitHub Pages
- Website: https://shyamalschandra.github.io/Yankovinator/

## Note on older migration docs

Some repository markdown files describe an unfinished Foundation Models migration. **The shipped product uses Ollama.** Prefer this guide and `README.md` for current instructions.
