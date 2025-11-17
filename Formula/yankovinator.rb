# Homebrew formula for Yankovinator
# This formula downloads pre-built binaries from GitHub Releases
# To use this formula, place it in your Homebrew tap repository:
# https://github.com/shyamalschandra/homebrew-yankovinator

class Yankovinator < Formula
  desc "Convert songs into parodies with theme-based constraints using llama on Ollama"
  homepage "https://github.com/shyamalschandra/Yankovinator"
  version "1.01"
  # Requires macOS 13.0+ for Ollama support
  depends_on :macos => :ventura
  
  # Determine architecture
  if Hardware::CPU.arm?
    arch = "arm64"
  else
    arch = "x86_64"
  end
  
  # Use universal binary if available, otherwise fall back to architecture-specific
  # Update these URLs after creating a GitHub release
  url "https://github.com/shyamalschandra/Yankovinator/releases/download/v#{version}/yankovinator-universal.tar.gz"
  # Alternative: use architecture-specific binary
  # url "https://github.com/shyamalschandra/Yankovinator/releases/download/v#{version}/yankovinator-#{arch}.tar.gz"
  
  # Calculate SHA256 after creating the release
  # Run: shasum -a 256 yankovinator-universal.tar.gz
  # Note: This will be updated after the GitHub release is created with proper universal binary
  sha256 "0dca2f61a9fee93abbfea5563f3eda6f69596bc234c6e794b27ba2d15750fe8e"  # Temporary - update after GitHub Actions builds proper universal binary
  
  def install
    # Extract and install binaries
    bin.install "yankovinator"
    bin.install "keyword-generator"
    bin.install "benchmark" if File.exist?("benchmark")
  end
  
  test do
    system "#{bin}/yankovinator", "--help"
    system "#{bin}/keyword-generator", "--help"
    system "#{bin}/benchmark", "--help" if File.exist?("#{bin}/benchmark")
  end
end
