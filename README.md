# Yankovinator

**Copyright (C) 2025, Shyamal Suhana Chandra**

**Invented by Shyamal Chandra**

Contact **ssc56@duck.com** to license code for commercial and non-commercial purposes.

Yankovinator is a Swift package that converts songs into parodies using Apple's NaturalLanguage framework and a local [Ollama](https://ollama.ai) LLM (`llama3.2:3b` by default). It preserves syllable structure, rhyme scheme, capitalization, and punctuation while steering lyrics with theme keywords.

The **`yankovinator` CLI (v1.06.0+)** runs in **batch mode only**: put songs in `--input-dir`, one theme file per entry in `--themes-dir`, and read parodies from `--output-dir` as `<theme>/<song>.parody.txt`. Use **`benchmark`** for single-file timing, or the **Swift library** for one-off generation in code.

**Website:** https://shyamalschandra.github.io/Yankovinator/

## Features

- Syllable-accurate parody generation (word-by-word matching)
- Automatic rhyme detection and enforcement
- Semantic coherence across lines (context-aware generation)
- Theme advancement (develop themes, not only mention keywords)
- Capitalization and punctuation matching
- Theme-based keyword integration
- Automatic keyword generation from subjects via Ollama
- Oxford English Dictionary (1913 / Webster) word suggestions for richer substitutions
- Unsupervised NLP helpers: embedding lexical substitution, rhyme clustering, next-line coherence critic
- NaturalLanguage framework integration
- Local or cloud Ollama integration (`llama3.2:3b` by default; any `--ollama-url`)
- Word-by-word **part-of-speech** matching and **OED**-filtered substitutions (v1.04.9+)
- **ParodyFitScorer** global ranking; optional **`--fit-optimize`** batch hill-climbing
- Parallel workers for batch jobs (`--workers` up to **128** / `--jobs`) with a **producer–consumer queue** (up to **128** concurrent consumers; optional **`--consumers`** cap)
- Batch **TUI progress** on stderr (**alternate screen**, full Unicode/color/emoji); one row per worker (`--no-progress` for plain logs)
- Batch-only **`yankovinator` CLI**: required `--input-dir`, `--themes-dir`, `--output-dir` (no single-file lyrics arg or `--keywords`)
- Combinatorial batch: every song × every theme via `--input-dir` + `--themes-dir`
- Multi-candidate ranking: `--candidates` up to **64** generates and scores variants per song×theme
- CLI tools: `yankovinator`, `keyword-generator`, `benchmark`
- XCTest suite (unit + Ollama integration tests)
- LaTeX/Beamer docs and GitHub Pages site

## Requirements

- Swift 5.10 or later
- macOS 13.0+ (iOS 16.0+ for library use)
- Ollama installed and running
- `llama3.2:3b` downloaded in Ollama (`ollama pull llama3.2:3b`)
- **For `swift test`:** full Xcode app (Command Line Tools alone do not provide XCTest)
- Homebrew (optional, for Homebrew install)

## Installation

### Pre-built binaries (recommended)

Download from [GitHub Releases](https://github.com/shyamalschandra/Yankovinator/releases) (current: **v1.06.3**). No Swift toolchain required.

```bash
curl -L -o yankovinator-universal.tar.gz \
  https://github.com/shyamalschandra/Yankovinator/releases/download/v1.06.3/yankovinator-universal.tar.gz

tar -xzf yankovinator-universal.tar.gz
sudo mv yankovinator keyword-generator /usr/local/bin/
# Optional if present in the archive:
# sudo mv benchmark /usr/local/bin/

yankovinator --help
keyword-generator --help
```

See [docs/RELEASES.md](docs/RELEASES.md) for architecture-specific downloads and troubleshooting.

### Homebrew

```bash
brew tap shyamalschandra/yankovinator
brew install yankovinator

yankovinator --help
keyword-generator --help
```

The formula installs pre-built binaries from GitHub Releases.

### Build from source

```bash
git clone https://github.com/shyamalschandra/Yankovinator.git
cd Yankovinator
swift build
```

Then install and start Ollama (see [Ollama Installation](#ollama-installation)).

## Usage

Yankovinator ships three CLI tools:

| Tool | Purpose |
|---|---|
| `yankovinator` | Batch parodies: all songs in `--input-dir` × all themes in `--themes-dir` |
| `keyword-generator` | Generate `keyword: definition` pairs from subjects |
| `benchmark` | Measure generation performance (single lyrics + keywords file) |

### Keyword generator

```bash
swift run keyword-generator <subject1> [subject2] ... [options]
```

**Options:**

- `--count, -c <number>`: Number of keyword pairs (default: 10)
- `--ollama-url, -u <url>`: Ollama API base URL (local or cloud; default: `http://localhost:11434`)
- `--model, -m <name>`: Ollama model (default: `llama3.2:3b`)
- `--output, -o <file>`: Output path (default: stdout)
- `--workers, --jobs <n>`: Max parallel subject jobs (1–**128**)
- `--verbose, -v`: Verbose output

```bash
swift run keyword-generator "artificial intelligence" --output ai_keywords.txt
swift run keyword-generator "space exploration" "NASA" --count 15 --output space_keywords.txt
swift run keyword-generator "ai" "space" "music" --workers 10 \
  --ollama-url https://ollama.example.com --output keywords.txt
```

### Parody generator (batch)

Every run is **songs × themes**. Each file in `--themes-dir` is a theme (`keyword: definition` lines). Outputs land under **`--output-dir/<theme-stem>/<song-stem>.parody.txt`**.

**Swift (development):**

```bash
swift run yankovinator --input-dir <songs-dir> --themes-dir <themes-dir> --output-dir <out-dir> [options]
```

**Wrapper script** (trims stray whitespace from arguments):

```bash
./yankovinator.sh --input-dir <songs-dir> --themes-dir <themes-dir> --output-dir <out-dir> [options]
```

**Required:**

- `--input-dir <dir>`: Directory of `.txt` lyrics files
- `--themes-dir <dir>`: Directory of theme keyword `.txt` files (`keyword: definition` per line)
- `--output-dir <dir>`: Output root (`<theme>/<song>.parody.txt`)

**Optional:**

- `--ollama-url, -u <url>`: Ollama API base URL (local or cloud)
- `--model, -m <name>`: Ollama model (default: `llama3.2:3b`)
- `--workers, --jobs <n>`: Parallel worker count (1–**128**). Consumer pool = min(workers, 128, `OLLAMA_NUM_PARALLEL` on localhost) unless `--consumers` is set.
- `--consumers <n>`: Cap in-flight consumer tasks (1–128; default follows `--workers`).
- `--ollama-num-parallel <n>` (alias `--ollama-num-workers`): Ollama server `OLLAMA_NUM_PARALLEL` (or set env before `ollama serve`; see [Ollama FAQ](https://docs.ollama.com/faq)).
- `--candidates <n>`: Generate N ranked variants per song×theme (1–**64**)
- `--fit-optimize`: Extra Ollama passes to hill-climb syllable/POS/coherence fit in batch (slower, higher scores)
- `--keep-candidates`: Also write ranked variants under `<song>.candidates/`
- `--force`: Allow songs×themes×candidates totals larger than 100 generations
- `--ollama-timeout <sec>`: Per-request Ollama HTTP timeout (30–900; heavy `:cloud` models default to 600s)
- `--no-progress`: Disable stderr progress bar for batch / multi-candidate runs
- `--midi-progress`: Lightweight MIDI cues per worker bar (macOS, interactive terminal only)
- `--no-cloud-prescription`: Disable auto tuning for heavy `:cloud` models (worker cap, 600s timeout, fast batch coherence)
- `--analyze, -a`: Show syllable analysis
- `--verbose, -v`: Verbose output

**Quick start (local Ollama):**

```bash
mkdir -p songs themes out
cp data/example_lyrics.txt songs/song.txt
cp data/example_keywords.txt themes/space.txt

swift run yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out --verbose
# → out/space/song.parody.txt
```

**Rank multiple candidates per song×theme:**

```bash
swift run yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \
  --candidates 10 --keep-candidates --verbose
# Best: out/<theme>/<song>.parody.txt
# All ranked: out/<theme>/<song>.candidates/
# If songs×themes×candidates > 100, add --force
```

**Cloud Ollama (10 workers):**

```bash
swift run yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \
  --ollama-url https://ollama.example.com --workers 10 --verbose
```

**Ollama server parallelism (local `ollama serve`):**

Match [Ollama’s `OLLAMA_NUM_PARALLEL`](https://docs.ollama.com/faq) to your `--workers` / consumer pool (e.g. 10):

```bash
export OLLAMA_NUM_PARALLEL=10   # set before starting the server; restart required
ollama serve
```

The CLI reads `$OLLAMA_NUM_PARALLEL` on `localhost` or you can pass `--ollama-num-parallel 10`.

**Heavy cloud batch (`qwen3.5:397b-cloud`, etc.):** stderr **prescription** may cap parallel HTTP workers at **64**, sets **600s** timeout if unset, and uses batch fast path with checkpoints. Use **`--no-cloud-prescription`** for the full `--workers` count (up to 128).

**High-throughput cloud batch (64 workers):**

```bash
yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \
  --workers 64 --ollama-num-workers 64 --no-cloud-prescription \
  --candidates 20 --fit-optimize --force --verbose
```

### Benchmark

```bash
swift run benchmark \
  --lyrics data/example_lyrics.txt \
  --keywords data/example_keywords.txt \
  --iterations 5
```

```bash
swift run benchmark \
  --lyrics data/example_lyrics.txt \
  --keywords data/example_keywords.txt \
  --iterations 10 \
  --workers 10 \
  --ollama-url https://ollama.example.com
```

### Programmatic usage

```swift
import Yankovinator

let lyrics = [
    "Twinkle twinkle little star",
    "How I wonder what you are"
]

let keywords = [
    "space": "the physical universe beyond Earth",
    "stars": "luminous celestial bodies"
]

let parody = try await Yankovinator.generateParody(
    originalLyrics: lyrics,
    keywords: keywords,
    ollamaURL: "http://localhost:11434",
    ollamaModel: "llama3.2:3b"
)

for line in parody {
    print(line)
}
```

## Input format

### Batch layout

```
songs/           # --input-dir: one .txt file per song (stem = job id)
  twinkle.txt
  verse2.txt
themes/          # --themes-dir: one .txt file per theme
  space.txt
  science.txt
out/             # --output-dir
  space/
    twinkle.parody.txt
  science/
    twinkle.parody.txt
```

### Lyrics file (one song)

One line per verse (empty lines are preserved):

```
Twinkle twinkle little star
How I wonder what you are
Up above the world so high
Like a diamond in the sky
```

Sample: [`data/example_lyrics.txt`](data/example_lyrics.txt)

### Theme / keywords file (one theme)

Format: `keyword: definition`

```
science: the study of natural phenomena
space: the physical universe beyond Earth
exploration: the action of traveling to discover
```

Sample: [`data/example_keywords.txt`](data/example_keywords.txt)

## Testing

XCTest needs the Xcode developer directory:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
```

The suite includes:

- Unit tests for syllable counting
- Keyword extraction tests
- Integration tests for Ollama connection and parody generation

Integration tests require Ollama with `llama3.2:3b`. If Ollama is unavailable, those tests skip gracefully.

Suggested local smoke checks:

```bash
swift build
swift run yankovinator --help
swift run keyword-generator --help
swift run benchmark --help
npm run build   # GitHub Pages TypeScript
```

## Documentation

| Resource | Description |
|---|---|
| [QUICK_START.md](QUICK_START.md) | Fast path from clone to first parody |
| [RELEASE_NOTES_v1.06.3.md](RELEASE_NOTES_v1.06.3.md) | Latest release notes (ANSI alt-screen TUI fix) |
| [RELEASE_NOTES_v1.06.2.md](RELEASE_NOTES_v1.06.2.md) | Superseded ncurses experiment |
| [RELEASE_NOTES_v1.06.1.md](RELEASE_NOTES_v1.06.1.md) | Parallel batch crash fix |
| [RELEASE_NOTES_v1.06.0.md](RELEASE_NOTES_v1.06.0.md) | Batch-only CLI |
| [docs/README.md](docs/README.md) | GitHub Pages site source |
| [docs/RELEASES.md](docs/RELEASES.md) | Binary release install guide |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Pages deployment status |
| `docs/yankovinator.tex` | Technical paper (LaTeX) |
| `docs/presentation.tex` | Beamer slides |
| `docs/reference.tex` | API reference manual |

Generate PDFs:

```bash
cd docs
pdflatex yankovinator.tex
pdflatex presentation.tex
pdflatex reference.tex
```

## Architecture

### Core components

1. **SyllableCounter** — syllable structure via NaturalLanguage + heuristics
2. **RhymeSchemeAnalyzer** — baseline rhyme groups / schemes
3. **UnsupervisedRhymeClustering** — phonetic + embedding rhyme discovery (unlabeled)
4. **LexicalSubstitutionEngine** — syllable-matched NLEmbedding neighbors (MLM-style)
5. **CoherenceCritic** — next-line surprise / coherence scoring (embedding + optional Ollama)
6. **OEDDictionary** — dictionary-backed word suggestions
7. **OllamaClient** — Ollama HTTP API (AsyncHTTPClient)
8. **ParodyGenerator** — generation + refinement pipeline
9. **BenchmarkRunner** — timing harness for CLI benchmarking
10. **Yankovinator** — public library facade

### Technology stack

- Swift 5.10+ / SwiftPM
- NaturalLanguage
- Ollama (`llama3.2:3b` default)
- AsyncHTTPClient
- ArgumentParser
- XCTest

## Algorithm (high level)

1. Analyze syllable structure (line totals and per-word patterns)
2. Detect rhyme scheme from the original lyrics
3. For each non-empty line:
   - Apply syllable, rhyme, keyword, and context constraints
   - Request a candidate from Ollama
   - Refine word-by-word syllables and semantic coherence
   - Match capitalization and punctuation to the original
4. Preserve empty-line structure in the output

## Ollama installation

### Method 1: Ollama GUI (recommended)

1. Download from [https://ollama.ai/download](https://ollama.ai/download) or `brew install --cask ollama-app`
2. Launch Ollama from Applications
3. Pull `llama3.2:3b` in the UI or via CLI

### Method 2: Homebrew CLI

```bash
brew install ollama
ollama serve
ollama pull llama3.2:3b
ollama list
```

### Verify

```bash
curl http://localhost:11434/api/tags
ollama run llama3.2:3b "Hello, how are you?"
```

## Troubleshooting

### Ollama not running

```bash
curl http://localhost:11434/api/tags
# GUI: open Ollama from Applications
# CLI: ollama serve
```

### Model not found

```bash
ollama list
ollama pull llama3.2:3b
ollama show llama3.2:3b
```

### `swift test` fails with `no such module 'XCTest'`

Point at Xcode, not Command Line Tools:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# or for a single shell:
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
```

### Connection refused

1. Confirm Ollama is running
2. Check the port: `lsof -i :11434`
3. Override URL if needed: `--ollama-url http://localhost:11434`

### Syllable count mismatch

Syllable counting uses heuristics and may differ on unusual words; that is expected.

## License

Copyright (C) 2025, Shyamal Suhana Chandra

Invented by Shyamal Chandra

Contact **ssc56@duck.com** to license code for commercial and non-commercial purposes.

## References

- [Apple NaturalLanguage Framework](https://developer.apple.com/documentation/NaturalLanguage)
- [Ollama Documentation](https://ollama.ai/docs)
- [Ollama Download](https://ollama.ai/download)
- [Swift Package Manager](https://swift.org/package-manager/)
- [Yankovinator on GitHub Pages](https://shyamalschandra.github.io/Yankovinator/)
