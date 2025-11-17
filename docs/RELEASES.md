# Binary Releases

Yankovinator provides pre-built universal binaries for macOS, eliminating the need to build from source.

## Downloading Binaries

### From GitHub Releases

1. Visit the [Releases page](https://github.com/shyamalschandra/yankovinator/releases)
2. Download the appropriate binary for your system:
   - **Universal Binary** (recommended): Works on both Intel and Apple Silicon Macs
   - **Intel (x86_64)**: For Intel-based Macs
   - **Apple Silicon (arm64)**: For Apple Silicon Macs

### Installation

```bash
# Download the universal binary
curl -L -o yankovinator-universal.tar.gz \
  https://github.com/shyamalschandra/yankovinator/releases/download/v1.01/yankovinator-universal.tar.gz

# Extract
tar -xzf yankovinator-universal.tar.gz

# Install to /usr/local/bin (requires sudo)
sudo mv yankovinator keyword-generator /usr/local/bin/

# Or install to ~/.local/bin (no sudo required)
mkdir -p ~/.local/bin
mv yankovinator keyword-generator ~/.local/bin/
export PATH="$HOME/.local/bin:$PATH"  # Add to ~/.zshrc or ~/.bash_profile
```

### Verification

```bash
# Verify installation
yankovinator --help
keyword-generator --help

# Check binary architecture (for universal binary)
file $(which yankovinator)
lipo -info $(which yankovinator)  # Should show both architectures
```

## Homebrew Installation

### Using a Homebrew Tap

1. Create a Homebrew tap repository (if not already created):
   ```bash
   # Create repository: homebrew-yankovinator
   # Place the Formula/yankovinator.rb file there
   ```

2. Install via Homebrew:
   ```bash
   brew tap shyamalschandra/yankovinator
   brew install yankovinator
   ```

### Updating the Homebrew Formula

After creating a new release:

1. Update the version in `Formula/yankovinator.rb`
2. Calculate the SHA256 checksum:
   ```bash
   shasum -a 256 yankovinator-universal.tar.gz
   ```
3. Update the `sha256` field in the formula
4. Commit and push to your Homebrew tap repository

## Creating a Release

### Automatic Release via GitHub Actions

1. **Tag a release:**
   ```bash
   git tag -a v1.0.0 -m "Release version 1.0.0"
   git push origin v1.0.0
   ```

2. The GitHub Actions workflow will automatically:
   - Build binaries for both architectures
   - Create universal binaries
   - Upload to GitHub Releases
   - Generate checksums

### Manual Release

1. **Trigger workflow manually:**
   - Go to Actions → Build and Release
   - Click "Run workflow"
   - Enter version tag (e.g., `v1.0.0`)

2. **Or create release manually:**
   - Build locally:
     ```bash
     swift build -c release
     ```
   - Create universal binary:
     ```bash
     # Build for both architectures
     swift build -c release  # arm64
     cp .build/.../yankovinator dist/arm64/
     arch -x86_64 swift build -c release  # x86_64
     cp .build/.../yankovinator dist/x86_64/
     
     # Create universal binary
     lipo -create dist/x86_64/yankovinator dist/arm64/yankovinator \
       -output dist/universal/yankovinator
     ```
   - Upload to GitHub Releases

## Binary Structure

Each release contains:
- `yankovinator`: Main parody generation tool
- `keyword-generator`: Keyword generation tool
- Checksum files (`.sha256`) for verification

## Troubleshooting

### Binary not executable

```bash
chmod +x yankovinator keyword-generator
```

### Architecture mismatch

If you get architecture errors:
- Use the universal binary (recommended)
- Or download the architecture-specific binary for your Mac

### Verification failed

Check the SHA256 checksum:
```bash
shasum -a 256 yankovinator-universal.tar.gz
# Compare with the .sha256 file from the release
```
