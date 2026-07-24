# Yankovinator v1.03.1

## What's new

- **Combinatorial batch:** `--themes-dir` + `--input-dir` runs every song × every theme in parallel
- Outputs nested as `out/<theme>/<song>.parody.txt`
- One song × many themes: `yankovinator song.txt --themes-dir ./themes --output-dir ./out`
- Safety gate: songs×themes > 100 requires `--force`
- Docs / README / Homebrew caveats updated for cross-product usage

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
  https://github.com/shyamalschandra/Yankovinator/releases/download/v1.03.1/yankovinator-universal.tar.gz
tar -xzf yankovinator-universal.tar.gz
sudo mv yankovinator keyword-generator benchmark /usr/local/bin/
```

## Combinatorial example

```bash
yankovinator --input-dir ./songs --themes-dir ./themes \
  --output-dir ./out --workers 10 --verbose
# add --force if songs×themes > 100
```
