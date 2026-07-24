# Yankovinator v1.02.1

## Bug fix

- **Crash fix:** eliminate a data race in `OEDDictionary` where background dictionary loading mutated shared state during parody generation (segfault / `NSInvalidArgumentException` after coherence regenerate)
- Harden `NLEmbedding` usage (`contains` before `neighbors` / `distance`)
- Safer capitalization matching (no nested `NLTokenizer` enumeration)
- Clearer CLI validation for empty/`--flag` values after `--output` / `--model`

## Install

### Homebrew

```bash
brew tap shyamalschandra/yankovinator
brew upgrade yankovinator
# or: brew install yankovinator
```

### Universal binary

```bash
curl -L -o yankovinator-universal.tar.gz \
  https://github.com/shyamalschandra/Yankovinator/releases/download/v1.02.1/yankovinator-universal.tar.gz
tar -xzf yankovinator-universal.tar.gz
sudo mv yankovinator keyword-generator benchmark /usr/local/bin/
```

## Usage note

Prefer:

```bash
yankovinator lyrics.txt --keywords themes.txt -a -v --output parody.txt
```

Avoid empty option values like `--output  --model  -a -v`.
