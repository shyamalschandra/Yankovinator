# Yankovinator v1.06.14

## Cloud DNS / connectivity resilience

Hard failures when Ollama returns **HTTP 502** with upstream DNS errors for `ollama.com` (`no such host`, `i/o timeout`, etc.) no longer abort an entire cloud batch after retries:

- **Retriable DNS/connectivity class** — longer backoff and more attempts than ordinary 429 on `:cloud` models
- **Batch isolation** — one failed song×theme×candidate is recorded and skipped; other units continue; durable progress stays under `--output-dir/.yankovinator`
- **Cloud preflight** — before heavy work, probe generate and print an actionable message if `ollama.com` is unreachable (VPN/DNS/firewall/offline), suggesting retry later or a local model
- Clearer errors: **DNS/connectivity to ollama.com** instead of a bare 502 tip

## Install

```bash
./scripts/install-local.sh ~/.local/bin
# or after release:
brew upgrade shyamalschandra/yankovinator/yankovinator
yankovinator --version   # → 1.06.14
```

## Example

```bash
yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \
  --model gemma4:31b-cloud --workers 10 --candidates 20 --keep-candidates --force --verbose
```

Note: cloud models still require DNS to resolve `ollama.com` from the machine running Ollama.
