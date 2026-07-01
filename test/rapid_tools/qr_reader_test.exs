defmodule RapidTools.QrReaderTest do
  use ExUnit.Case, async: false

  alias RapidTools.QrReader
  alias RapidTools.TestSupport.ImageFixtures

  test "available?/0 is true when zbarimg exists" do
    if System.find_executable("zbarimg") do
      assert QrReader.available?()
    else
      refute QrReader.available?()
    end
  end

  test "read/1 decodes a QR code image" do
    source_path =
      ImageFixtures.qr_png_path!("https://rapid.tools/qr-test", "qr-reader-decode.png")

    assert {:ok, "https://rapid.tools/qr-test"} = QrReader.read(source_path)
  end

  test "read/1 returns no_qr_found for images without a QR code" do
    source_path = ImageFixtures.tiny_png_path!("qr-reader-no-code.png")

    assert {:error, :no_qr_found} = QrReader.read(source_path)
  end

  test "read/1 returns source_file_not_found for missing files" do
    assert {:error, :source_file_not_found} =
             QrReader.read(
               "/tmp/rapid-tools-missing-qr-#{System.unique_integer([:positive])}.png"
             )
  end
end
