# Homebrew formula for Yankovinator
# Tap: https://github.com/shyamalschandra/homebrew-yankovinator
#
#   brew tap shyamalschandra/yankovinator
#   brew install yankovinator

class Yankovinator < Formula
  desc "Convert songs into parodies with theme-based constraints using llama on Ollama"
  homepage "https://github.com/shyamalschandra/Yankovinator"
  url "https://github.com/shyamalschandra/Yankovinator/releases/download/v1.06.3/yankovinator-universal.tar.gz"
  sha256 "dcf4a297fd37a24ec80d4cc32d8486121b45cc06210d3caa2684245c8c24f971"
  license :cannot_represent

  depends_on macos: :ventura

  def install
    bin.install "yankovinator"
    bin.install "keyword-generator"
    bin.install "benchmark" if File.exist?("benchmark")
  end

  def caveats
    <<~EOS
      Yankovinator requires Ollama (local or cloud) with the llama3.2:3b model:

        brew install --cask ollama-app
        # or: brew install ollama && ollama serve
        ollama pull llama3.2:3b

      Batch (songs × themes):
        yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \\
          --ollama-url https://ollama.example.com --workers 10

      Many candidates per song×theme:
        yankovinator --input-dir ./songs --themes-dir ./themes \\
          --output-dir ./out --workers 10 --candidates 10 --keep-candidates
        # best: out/<theme>/<song>.parody.txt
        # add --force if songs×themes×candidates > 100

      Docs: https://github.com/shyamalschandra/Yankovinator
      Site: https://shyamalschandra.github.io/Yankovinator/
    EOS
  end

  test do
    assert_match "USAGE", shell_output("#{bin}/yankovinator --help")
    assert_match "USAGE", shell_output("#{bin}/keyword-generator --help")
    assert_match "USAGE", shell_output("#{bin}/benchmark --help") if (bin/"benchmark").exist?
  end
end
