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

  test "convert/2 rejects non-existent source files" do
    output_dir = ImageFixtures.temp_dir!("missing-source")

    assert {:error, :source_file_not_found} =
             AudioConverter.convert("/non/existent/file.wav", "mp3", output_dir: output_dir)
  end

  test "convert/2 converts wav to ogg" do
    source_path = ImageFixtures.tiny_wav_path!("source-for-ogg.wav")
    output_dir = ImageFixtures.temp_dir!("ogg-conversion")

    assert {:ok, result} = AudioConverter.convert(source_path, "ogg", output_dir: output_dir)

    assert result.target_format == "ogg"
    assert result.media_type == "audio/ogg"
    assert File.exists?(result.output_path)
  end

  test "convert/2 converts wav to aac" do
    source_path = ImageFixtures.tiny_wav_path!("source-for-aac.wav")
    output_dir = ImageFixtures.temp_dir!("aac-conversion")

    assert {:ok, result} = AudioConverter.convert(source_path, "aac", output_dir: output_dir)

    assert result.target_format == "aac"
    assert result.media_type == "audio/aac"
    assert File.exists?(result.output_path)
  end
end
