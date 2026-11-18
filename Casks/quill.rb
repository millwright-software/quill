cask "quill" do
  version "0.4.3"
  sha256 "b5bfe640bce618db7711c38211c11938d751d84f628d7b78e4f13de7a0a8c289"

  url "https://github.com/millwright-software/quill/releases/download/v#{version}/Quill.zip"
  name "Quill"
  desc "Hold-to-talk dictation and meeting recorder, on-device"
  homepage "https://millwrightsoftware.com/quill/"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "Quill.app"

  uninstall quit: "com.millwright.quill"

  zap trash: [
    "~/Library/Application Support/FluidAudio",
    "~/Library/Application Support/Quill",
    "~/Library/Logs/Quill.log",
    "~/Library/Preferences/com.millwright.quill.plist",
  ]
end
