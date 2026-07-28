# Binary Releases

Yankovinator publishes pre-built macOS binaries so you can install without a Swift toolchain.

**Current release:** [v1.06.13](https://github.com/shyamalschandra/Yankovinator/releases/tag/v1.06.13)

## What each archive contains

- `yankovinator` — parody generator CLI
- `yankovinator-tui` — Rust/ratatui dashboard: color boxes + emoji bars with elapsed/remain per worker (v1.06.10+)
- `keyword-generator` — theme keyword generator CLI
- `benchmark` — performance benchmark CLI (when included in the build)
- `*.sha256` — checksums for verification

## Download

1. Open [Releases](https://github.com/shyamalschandra/Yankovinator/releases)
2. Choose an archive:
   - **Universal** (recommended): Intel + Apple Silicon
   - **arm64**: Apple Silicon
   - **x86_64**: Intel

### Install (universal)

```bash
curl -L -o yankovinator-universal.tar.gz \
  https://github.com/shyamalschandra/Yankovinator/releases/download/v1.06.13/yankovinator-universal.tar.gz

# Verify checksum (compare to the release .sha256 asset)
shasum -a 256 yankovinator-universal.tar.gz

tar -xzf yankovinator-universal.tar.gz

# System-wide
sudo mv yankovinator keyword-generator /usr/local/bin/
# sudo mv benchmark /usr/local/bin/   # if present

# Or user-local
mkdir -p ~/.local/bin
mv yankovinator keyword-generator ~/.local/bin/
export PATH="$HOME/.local/bin:$PATH"
```

### Verify

```bash
yankovinator --help
keyword-generator --help
benchmark --help   # if installed

file "$(which yankovinator)"
lipo -info "$(which yankovinator)"   # universal should list both archs
```

Binaries still require a running Ollama instance and the `llama3.2:3b` model. See the root [README.md](../README.md).

## Homebrew

```bash
brew tap shyamalschandra/yankovinator
brew install yankovinator
# or upgrade:
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
yankovinator --version   # → 1.06.13+
```

After a new GitHub release, sync the tap from this repo:

```bash
./update-homebrew-tap.sh 1.06.13
```

Local formula template: [`Formula/yankovinator.rb`](../Formula/yankovinator.rb). Tap: [homebrew-yankovinator](https://github.com/shyamalschandra/homebrew-yankovinator).

## Creating a release

### Automatic (GitHub Actions)

```bash
./scripts/certification-battery.sh   # must pass
git tag -a v1.06.8 -m "Release version 1.06.8"
git push origin v1.06.8
```

The **Build and Release** workflow builds architecture artifacts, packages archives, and uploads release assets.

### Manual workflow dispatch

Actions → **Build and Release** → **Run workflow** → enter a version tag (for example `v1.06.0`).

### Local packaging sketch

```bash
swift build -c release
# copy products into dist/{arm64,x86_64}/ then:
lipo -create dist/x86_64/yankovinator dist/arm64/yankovinator \
  -output dist/universal/yankovinator
```

## Troubleshooting

### Not executable

```bash
chmod +x yankovinator keyword-generator benchmark
```

### Architecture mismatch

Use the universal archive, or the archive matching your Mac (`uname -m`).

### Checksum mismatch

```bash
shasum -a 256 yankovinator-universal.tar.gz
# compare with the published .sha256 file
```
