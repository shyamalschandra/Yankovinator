# Homebrew formula for Yankovinator
# Tap: https://github.com/shyamalschandra/homebrew-yankovinator
#
#   brew tap shyamalschandra/yankovinator
#   brew install yankovinator

class Yankovinator < Formula
  desc "Convert songs into parodies with theme-based constraints using Ollama"
  homepage "https://github.com/shyamalschandra/Yankovinator"
  url "https://github.com/shyamalschandra/Yankovinator/releases/download/v1.06.11/yankovinator-universal.tar.gz"
  sha256 "0172e4f398016108ef52acfdc3ee2481cfd5a5af5e5990b9bca641f8402b92a2"
  version "1.06.11"
  license :cannot_represent

  depends_on macos: :ventura

  livecheck do
    url :stable
    strategy :github_latest
  end

  def install
    bin.install "yankovinator"
    bin.install "keyword-generator"
    bin.install "yankovinator-tui" if File.exist?("yankovinator-tui")
    bin.install "benchmark" if File.exist?("benchmark")
  end

  def caveats
    <<~EOS
      Yankovinator requires Ollama (local or cloud) with a model such as llama3.2:3b:

        brew install --cask ollama-app
        # or: brew install ollama && ollama serve
        ollama pull llama3.2:3b

      Batch (every song × every theme):
        yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \\
          --workers 10 --candidates 10 --keep-candidates --force

      Resume after Ctrl+C: re-run the same command (checkpoint in --output-dir/.yankovinator).
      Reset checkpoint: add --fresh-batch.

      Interactive progress: yankovinator-tui is installed beside yankovinator (Rust/ratatui).
      Disable: YANKOVINATOR_RUST_TUI=0

      Docs: https://github.com/shyamalschandra/Yankovinator
      Site: https://shyamalschandra.github.io/Yankovinator/
    EOS
  end

  test do
    assert_equal "1.06.11", shell_output("#{bin}/yankovinator --version").strip
    assert_match "USAGE", shell_output("#{bin}/yankovinator --help")
    assert_match "fresh-batch", shell_output("#{bin}/yankovinator --help")
    assert_match "USAGE", shell_output("#{bin}/keyword-generator --help")
    assert_match "USAGE", shell_output("#{bin}/benchmark --help") if (bin/"benchmark").exist?
    assert_predicate bin/"yankovinator-tui", :exist?
  end
end
