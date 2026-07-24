#!/bin/bash
# Benchmark script for Yankovinator (Ollama)

set -e

echo "=== Yankovinator Benchmark ==="
echo ""

if [ ! -f "data/example_lyrics.txt" ]; then
    echo "Error: Sample lyrics not found. Expected data/example_lyrics.txt"
    exit 1
fi

if [ ! -f "data/example_keywords.txt" ]; then
    echo "Error: Sample keywords not found. Expected data/example_keywords.txt"
    exit 1
fi

echo "Running Ollama benchmark..."
echo ""

echo "Building project..."
swift build -c release

echo "Running benchmark..."
swift run -c release benchmark \
  --lyrics data/example_lyrics.txt \
  --keywords data/example_keywords.txt \
  --iterations "${1:-1}"

echo ""
echo "Benchmark complete!"
