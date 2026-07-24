# Yankovinator v1.04

## What's new

- **`--candidates 10`:** generate N ranked parody variants per song×theme (default recommended: 10)
- Combinatorial explosion is now **songs × themes × candidates**, capped by `--workers`
- Best candidate is written to the normal output path; `--keep-candidates` saves ranked variants under `<song>.candidates/`
- Safety gate uses effective generations (`songs × themes × candidates`); above 100 requires `--force`
- Docs, README, and Homebrew caveats updated

## Install

### Homebrew

```bash
brew tap shyamalschandra/yankovinator
brew update
brew upgrade yankovinator
```

### Universal binary

```bash
curl -L -o yankovinator-universal.tar.gz \
  https://github.com/shyamalschandra/Yankovinator/releases/download/v1.04/yankovinator-universal.tar.gz
tar -xzf yankovinator-universal.tar.gz
sudo mv yankovinator keyword-generator benchmark /usr/local/bin/
```

## Combinatorial + 10 candidates

```bash
yankovinator --input-dir ./songs --themes-dir ./themes \
  --output-dir ./out \
  --workers 10 \
  --candidates 10 \
  --keep-candidates \
  --verbose
# add --force if songs×themes×candidates > 100
```
