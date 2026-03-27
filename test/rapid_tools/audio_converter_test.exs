defmodule RapidTools.AudioConverterTest do
  use ExUnit.Case, async: true

  alias RapidTools.AudioConverter
  alias RapidTools.TestSupport.ImageFixtures

  test "supported_formats/0 exposes common audio output formats" do
    assert AudioConverter.supported_formats() == ~w(mp3 wav ogg aac flac)
  end

  test "convert/2 converts an audio file into the target format" do
    source_path = ImageFixtures.tiny_wav_path!("source-for-mp3.wav")
    output_dir = ImageFixtures.temp_dir!("mp3-conversion")

    assert {:ok, result} = AudioConverter.convert(source_path, "mp3", output_dir: output_dir)
    assert result.target_format == "mp3"
    assert result.media_type == "audio/mpeg"
    assert String.ends_with?(result.output_path, ".mp3")
    assert File.exists?(result.output_path)
  end

  test "convert/2 rejects unsupported target formats" do
    source_path = ImageFixtures.tiny_wav_path!("source-for-opus.wav")
    output_dir = ImageFixtures.temp_dir!("opus-conversion")

    assert {:error, {:unsupported_target_format, "opus"}} =
             AudioConverter.convert(source_path, "opus", output_dir: output_dir)
  end
end
