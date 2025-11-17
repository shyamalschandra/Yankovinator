# Yankovinator

**Copyright (C) 2025, Shyamal Suhana Chandra**

**Invented by Shyamal Chandra**

Contact **ssc56@duck.com** to license code for commercial and non-commercial purposes.

Yankovinator is a Swift-based application that converts songs into parodies using Apple's NaturalLanguage framework and Ollama (llama3.2:3b) for intelligent text generation. The system maintains the original song's syllable structure while generating new lyrics that follow theme-based keyword constraints.

## Features

- ✅ Syllable-accurate parody generation (word-by-word matching)
- ✅ Automatic rhyme detection and enforcement
- ✅ Semantic coherence across lines (context-aware generation)
- ✅ Theme advancement (not just mention, but actively develop themes)
- ✅ Capitalization and punctuation matching (exact style preservation)
- ✅ Theme-based keyword integration
- ✅ Automatic keyword generation from subjects using Ollama
- ✅ NaturalLanguage framework integration
- ✅ Ollama integration (llama3.2:3b model)
- ✅ Command-line interface
- ✅ Comprehensive testing with XCTest
- ✅ Full documentation (LaTeX/Beamer)

## Requirements

- Swift 5.10 or later
- macOS 13.0+ or iOS 16.0+
- Ollama installed and running
- llama3.2:3b model downloaded in Ollama
- Homebrew (for Homebrew installation method)

**Note**: Yankovinator requires Ollama to be running locally. See the [Ollama Installation](#ollama-installation) section below for detailed setup instructions.

## Installation

### Pre-built Binaries (Recommended)

Download pre-built universal binaries from [GitHub Releases](https://github.com/shyamalschandra/Yankovinator/releases). No Swift toolchain required!

```bash
# Download the universal binary (works on both Intel and Apple Silicon)
curl -L -o yankovinator-universal.tar.gz \
  https://github.com/shyamalschandra/Yankovinator/releases/download/v1.01/yankovinator-universal.tar.gz

# Extract
tar -xzf yankovinator-universal.tar.gz

# Install to /usr/local/bin
sudo mv yankovinator keyword-generator /usr/local/bin/

# Verify installation
yankovinator --help
keyword-generator --help
```

See [RELEASES.md](docs/RELEASES.md) for detailed installation instructions and troubleshooting.

### Homebrew

Install via Homebrew using the tap:

```bash
# Add the tap
brew tap shyamalschandra/yankovinator

# Install Yankovinator
brew install yankovinator

# Verify installation
yankovinator --help
keyword-generator --help
```

The Homebrew formula downloads pre-built binaries from GitHub Releases, so no Swift toolchain is required.

### Build from Source

For development or if you prefer building from source:

#### 1. Clone the repository

```bash
git clone https://github.com/shyamalschandra/Yankovinator.git
cd Yankovinator
```

#### 2. Build the project

```bash
swift build
```

#### 3. Install and Set Up Ollama

Yankovinator requires Ollama to be installed and running. See the [Ollama Installation](#ollama-installation) section below for complete setup instructions.

## Usage

### Command Line Interface

Yankovinator provides two CLI tools:

1. **yankovinator**: Generates parodies from song lyrics
2. **keyword-generator**: Generates keyword:definition pairs from subjects using Ollama

#### Keyword Generator

Generate keyword:definition pairs for use with Yankovinator:

```bash
swift run keyword-generator <subject1> [subject2] ... [options]
```

**Options:**
- `--count, -c <number>`: Number of keyword pairs to generate (default: 10, max: 100)
- `--ollama-url, -u <url>`: Ollama API base URL (default: http://localhost:11434)
- `--model, -m <name>`: Ollama model name (default: llama3.2:3b)
- `--output, -o <file>`: Output file path (default: stdout)
- `--verbose, -v`: Verbose output

**Examples:**

```bash
# Generate 10 keywords about AI
swift run keyword-generator "artificial intelligence" --output ai_keywords.txt

# Generate 15 keywords about multiple subjects
swift run keyword-generator "space exploration" "NASA" --count 15 --output space_keywords.txt

# Generate keywords and print to stdout
swift run keyword-generator "machine learning" "deep learning" --verbose
```

#### Parody Generator

You can use Yankovinator in two ways:

#### Option 1: Direct Swift execution (recommended for development)

```bash
swift run yankovinator <lyrics-file> [options]
```

#### Option 2: Using the wrapper script (recommended for production, handles edge cases)

```bash
./yankovinator.sh <lyrics-file> [options]
```

The wrapper script automatically:
- Builds the project if needed
- Filters out empty arguments and whitespace issues
- Handles command-line parsing edge cases

**Options:**
- `--keywords, -k <file>`: Path to keywords file (format: `keyword: definition`)
- `--ollama-url, -u <url>`: Ollama API base URL (default: http://localhost:11434)
- `--model, -m <name>`: Ollama model name (default: llama3.2:3b)
- `--output, -o <file>`: Output file path (default: stdout)
- `--analyze, -a`: Show syllable analysis
- `--verbose, -v`: Verbose output

**Example (single line):**

```bash
swift run yankovinator lyrics.txt --keywords themes.txt --output parody.txt --analyze --verbose
```

**Example (with custom Ollama URL and model):**

```bash
swift run yankovinator lyrics.txt \
  --keywords themes.txt \
  --ollama-url http://localhost:11434 \
  --model llama3.2:3b \
  --output parody.txt
```

**Example (using wrapper script):**

```bash
./yankovinator.sh lyrics.txt --keywords themes.txt --output parody.txt --analyze --verbose
```

**Note:** If you encounter "Unexpected argument ' '" errors, use the wrapper script (`./yankovinator.sh`) which handles these edge cases automatically.

### Programmatic Usage

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

## Input Format

### Lyrics File

One line per verse:

```
Twinkle twinkle little star
How I wonder what you are
Up above the world so high
Like a diamond in the sky
```

### Keywords File

Format: `keyword: definition`

```
science: the study of natural phenomena
space: the physical universe beyond Earth
exploration: the action of traveling to discover
```

## Testing

Run the test suite:

```bash
swift test
```

The tests include:
- Unit tests for syllable counting
- Integration tests for parody generation
- Keyword extraction tests

**Note:** Integration tests require Ollama to be running with the llama3.2:3b model installed. They will be skipped if Ollama is not available.

## Documentation

### LaTeX Documentation

Generate PDF documentation:

```bash
cd docs
pdflatex yankovinator.tex
```

### Beamer Presentation

Generate presentation slides:

```bash
cd docs
pdflatex presentation.tex
```

### Reference Manual

Generate API reference manual:

```bash
cd docs
pdflatex reference.tex
```

The reference manual provides comprehensive API documentation including:
- Function signatures and parameters
- Return types and error handling
- Usage examples and best practices
- Configuration options
- Complete type definitions

## Architecture

### Core Components

1. **SyllableCounter**: Analyzes syllable structure using NaturalLanguage framework
2. **OllamaClient**: Interfaces with Ollama API for parody generation
3. **ParodyGenerator**: Orchestrates the parody creation process
4. **Yankovinator**: Main library interface

### Technology Stack

- **Swift 5.10+**: Primary programming language
- **NaturalLanguage**: Apple framework for linguistic analysis
- **Ollama**: Local LLM server (llama3.2:3b model)
- **AsyncHTTPClient**: HTTP client for Ollama API communication
- **ArgumentParser**: CLI argument parsing

## Algorithm

### Syllable Counting

The syllable counting algorithm uses:
1. NaturalLanguage tokenization for word separation
2. Vowel counting heuristics
3. Special case handling for silent 'e' and 'le' endings

### Parody Generation

1. Analyze original song's syllable structure (total and word-by-word)
2. Detect rhyming scheme automatically
3. For each line:
   - Extract syllable count requirement (total and word-by-word)
   - Determine rhyming constraints
   - Build prompt with theme keywords and semantic context
   - Request generation from Ollama (llama3.2:3b) with previous lines for coherence
   - Validate and clean response
   - Refine word-by-word syllable matching
   - Refine semantic coherence with previous lines
   - Correct punctuation to match original style
4. Return complete parody

### Semantic Coherence

Yankovinator employs advanced semantic coherence techniques:
- **Context Awareness**: Each line considers up to 8 previous lines for narrative continuity
- **Theme Advancement**: Lines actively advance the chosen theme, not just mention keywords
- **Semantic Refinement**: Dedicated refinement pass ensures lines work together thematically
- **Narrative Flow**: Maintains logical progression and consistent imagery throughout

## Benchmarking

Yankovinator includes a built-in benchmarking tool to measure performance:

```bash
swift run benchmark --lyrics data/test_short.txt --keywords data/test_keywords.txt --iterations 5
```

This will run multiple iterations and provide average performance metrics.

## Ollama Installation

Yankovinator requires Ollama to be installed and running on your macOS system. Follow these steps to set up Ollama:

### Method 1: Install Ollama GUI (Recommended)

1. **Download Ollama for macOS:**
   - Visit [https://ollama.ai/download](https://ollama.ai/download)
   - Download the macOS installer (`.dmg` file)

2. **Install Ollama:**
   - Open the downloaded `.dmg` file
   - Drag the Ollama icon to your Applications folder
   - Launch Ollama from Applications

3. **Verify Ollama is running:**
   - Look for the Ollama icon in your menu bar (top right)
   - Click the icon to open the Ollama GUI
   - The GUI will show "Ollama is running" when active

4. **Download the llama3.2:3b model:**
   - In the Ollama GUI, click "Models" or use the search bar
   - Search for "llama3.2:3b"
   - Click "Download" to install the model
   - Wait for the download to complete (approximately 2GB)

### Method 2: Install Ollama via Homebrew

1. **Install Ollama (choose one method):**
   
   **Option A: Install Ollama GUI App (Recommended for macOS):**
   ```bash
   brew install --cask ollama-app
   ```
   This installs the GUI application that runs automatically.
   
   **Option B: Install Ollama CLI:**
   ```bash
   brew install ollama
   ```

2. **Start Ollama service:**
   
   **If using GUI app (Option A):**
   - Launch Ollama from Applications
   - The app runs automatically in the background
   
   **If using CLI (Option B):**
   ```bash
   ollama serve
   ```
   (This will run in the foreground. For background service, see below)

3. **Download the llama3.2:3b model:**
   ```bash
   ollama pull llama3.2:3b
   ```

4. **Verify installation:**
   ```bash
   ollama list  # Should show llama3.2:3b
   ```

### Running Ollama as a Background Service

If you installed via Homebrew and want Ollama to run automatically:

1. **Create a LaunchAgent (macOS):**
   ```bash
   # Create the plist file
   cat > ~/Library/LaunchAgents/com.ollama.ollama.plist << EOF
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>Label</key>
       <string>com.ollama.ollama</string>
       <key>ProgramArguments</key>
       <array>
           <string>/usr/local/bin/ollama</string>
           <string>serve</string>
       </array>
       <key>RunAtLoad</key>
       <true/>
       <key>KeepAlive</key>
       <true/>
   </dict>
   </plist>
   EOF
   
   # Load the service
   launchctl load ~/Library/LaunchAgents/com.ollama.ollama.plist
   ```

2. **Or use the Ollama GUI** (automatically runs as a service)

### Verify Ollama Setup

Test that Ollama is working correctly:

```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# Test the model
ollama run llama3.2:3b "Hello, how are you?"
```

If you see a response, Ollama is working correctly!

## Troubleshooting

### Ollama not running

If you get connection errors, ensure Ollama is running:

```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# If not running, start it:
# GUI: Open Ollama from Applications
# CLI: ollama serve
```

### Model not found

If you get "Model not found" errors:

```bash
# List installed models
ollama list

# If llama3.2:3b is not listed, download it:
ollama pull llama3.2:3b

# Verify the model is available
ollama show llama3.2:3b
```

### Connection refused

If you get "Connection refused" errors:

1. Ensure Ollama is running (check menu bar icon or run `ollama serve`)
2. Verify Ollama is listening on the correct port:
   ```bash
   lsof -i :11434
   ```
3. Check if you need to use a different URL:
   ```bash
   yankovinator lyrics.txt --ollama-url http://localhost:11434
   ```

### Syllable count mismatch

The algorithm uses heuristics and may not be 100% accurate. This is expected behavior for complex words.

## License

Copyright (C) 2025, Shyamal Suhana Chandra

Invented by Shyamal Chandra

Contact **ssc56@duck.com** to license code for commercial and non-commercial purposes.

## References

- [Apple NaturalLanguage Framework](https://developer.apple.com/documentation/NaturalLanguage)
- [Ollama Documentation](https://ollama.ai/docs)
- [Ollama Download](https://ollama.ai/download)
- [Swift Package Manager](https://swift.org/package-manager/)

