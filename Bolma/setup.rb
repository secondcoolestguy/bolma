class Bolma < Formula
  desc "CLI layout engine for .bolma files written in Rust"
  homepage "https://github.com/secondcoolestguy/bolma"
  url "https://github.com/secondcoolestguy/bolma/archive/refs/tags/0.2.0.tar.gz"
  sha256 "6ee766806e076a723eb41924bed96ad2a5329b53a3b5f0dff1627e9f5bf820ef"
  license "GPL-3.0-only"

  depends_on "rust" => :build

  def install
    # Execute setup.rb using Homebrew's internal Ruby path
    system RUBY_PATH, "setup.rb"

    # Step into the 'Bolma' folder created by setup.rb and install the binary
    cd "Bolma" do
      system "cargo", "install", *std_cargo_args
    end
  end

  test do
    assert_match "Bolma CLI Tool", shell_output("#{bin}/bolma --help")
  end
end
