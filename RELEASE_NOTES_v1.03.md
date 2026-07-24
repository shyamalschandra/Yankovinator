# Yankovinator v1.03

## What's new

- **Parallel workers for cloud Ollama:** run up to 10 (max 32) independent jobs at once with `--workers` / `--jobs`
- **Batch parody mode:** `--input-dir` + `--output-dir` processes many `.txt` lyrics files concurrently (writes `<stem>.parody.txt`)
- `keyword-generator` and `benchmark` also accept `--workers` for parallel subjects / iterations
- HTTP connection pool sized for concurrent cloud Ollama requests
- Docs updated for local and cloud Ollama batch usage

## Install

### Homebrew

```bash
brew tap shyamalschandra/yankovinator
brew update
brew upgrade yankovinator
# or: brew install yankovinator
```

### Universal binary

```bash
curl -L -o yankovinator-universal.tar.gz \
  https://github.com/shyamalschandra/Yankovinator/releases/download/v1.03/yankovinator-universal.tar.gz
tar -xzf yankovinator-universal.tar.gz
sudo mv yankovinator keyword-generator benchmark /usr/local/bin/
```

## Parallel batch example (cloud Ollama)

```bash
mkdir -p songs out
# put lyrics .txt files in songs/

yankovinator --input-dir ./songs --output-dir ./out \
  --keywords themes.txt \
  --ollama-url https://ollama.example.com \
  --workers 10 \
  --verbose
```
