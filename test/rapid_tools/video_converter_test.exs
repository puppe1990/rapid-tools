defmodule RapidTools.VideoConverterTest do
  use ExUnit.Case, async: true

  alias RapidTools.TestSupport.ImageFixtures
  alias RapidTools.VideoConverter

  test "supported_formats/0 exposes the most common output formats" do
    assert VideoConverter.supported_formats() == ~w(mp4 mov webm mkv avi)
  end

  test "convert/2 converts a video into the target format" do
    source_path = ImageFixtures.tiny_mp4_path!("source-for-webm.mp4")
    output_dir = ImageFixtures.temp_dir!("webm-conversion")

    assert {:ok, result} = VideoConverter.convert(source_path, "webm", output_dir: output_dir)
    assert result.target_format == "webm"
    assert result.media_type == "video/webm"
    assert String.ends_with?(result.output_path, ".webm")
    assert File.exists?(result.output_path)
  end

  test "convert/2 rejects unsupported target formats" do
    source_path = ImageFixtures.tiny_mp4_path!("source-for-flv.mp4")
    output_dir = ImageFixtures.temp_dir!("flv-conversion")

    assert {:error, {:unsupported_target_format, "flv"}} =
             VideoConverter.convert(source_path, "flv", output_dir: output_dir)
  end

  test "convert/2 rejects mp4 files without a video stream" do
    source_path = ImageFixtures.audio_only_mp4_path!("audio-only-source.mp4")
    output_dir = ImageFixtures.temp_dir!("audio-only-conversion")

    assert {:error, :no_video_stream} =
             VideoConverter.convert(source_path, "webm", output_dir: output_dir)
  end
end
