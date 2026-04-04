defmodule RapidTools.AudioExtractorTest do
  use ExUnit.Case, async: true

  alias RapidTools.AudioExtractor
  alias RapidTools.TestSupport.ImageFixtures

  test "supported_formats/0 exposes the common audio output formats" do
    assert AudioExtractor.supported_formats() == ~w(mp3 wav ogg aac flac)
  end

  test "extract/2 extracts audio from a video into the target format" do
    source_path = ImageFixtures.tiny_mp4_path!("source-for-audio-extraction.mp4")
    output_dir = ImageFixtures.temp_dir!("audio-extraction")

    assert {:ok, result} = AudioExtractor.extract(source_path, "mp3", output_dir: output_dir)
    assert result.target_format == "mp3"
    assert result.media_type == "audio/mpeg"
    assert String.ends_with?(result.output_path, ".mp3")
    assert File.exists?(result.output_path)
  end

  test "extract/2 rejects unsupported target formats" do
    source_path = ImageFixtures.tiny_mp4_path!("source-for-audio-extraction-invalid.mp4")
    output_dir = ImageFixtures.temp_dir!("audio-extraction-invalid")

    assert {:error, {:unsupported_target_format, "opus"}} =
             AudioExtractor.extract(source_path, "opus", output_dir: output_dir)
  end

  test "extract/2 rejects mp4 files without an audio stream" do
    source_path = ImageFixtures.video_only_mp4_path!("video-only-source.mp4")
    output_dir = ImageFixtures.temp_dir!("video-only-audio-extraction")

    assert {:error, :no_audio_stream} =
             AudioExtractor.extract(source_path, "mp3", output_dir: output_dir)
  end
end
