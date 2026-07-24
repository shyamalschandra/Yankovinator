# Homebrew formula for Yankovinator
# Tap: https://github.com/shyamalschandra/homebrew-yankovinator
#
#   brew tap shyamalschandra/yankovinator
#   brew install yankovinator

class Yankovinator < Formula
  desc "Convert songs into parodies with theme-based constraints using llama on Ollama"
  homepage "https://github.com/shyamalschandra/Yankovinator"
  url "https://github.com/shyamalschandra/Yankovinator/releases/download/v1.02/yankovinator-universal.tar.gz"
  sha256 "86be4e2d9beae0a4a43ebced31dcce595f335b7066e2155b9a653b502f957aba"
  license :cannot_represent

  depends_on macos: :ventura

  def install
    bin.install "yankovinator"
    bin.install "keyword-generator"
    bin.install "benchmark" if File.exist?("benchmark")
  end

  def caveats
    <<~EOS
      Yankovinator requires a local Ollama server with the llama3.2:3b model:

        brew install --cask ollama-app
        # or: brew install ollama && ollama serve
        ollama pull llama3.2:3b

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
