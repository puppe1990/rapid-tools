defmodule RapidTools.VideoCompressorTest do
  use ExUnit.Case, async: true

  alias RapidTools.TestSupport.ImageFixtures
  alias RapidTools.VideoCompressor

  test "supported_presets/0 exposes the supported compression presets" do
    assert VideoCompressor.supported_presets() == ~w(small balanced high)
  end

  test "supported_resolutions/0 exposes the supported max resolutions" do
    assert VideoCompressor.supported_resolutions() == ~w(original 1080 720 480)
  end

  test "compress/2 compresses a video into mp4" do
    source_path = ImageFixtures.tiny_mp4_path!("compress-source.mp4")
    output_dir = ImageFixtures.temp_dir!("video-compressor")

    assert {:ok, result} =
             VideoCompressor.compress(source_path,
               preset: "balanced",
               max_resolution: "720",
               output_dir: output_dir
             )

    assert result.preset == "balanced"
    assert result.max_resolution == "720"
    assert result.media_type == "video/mp4"
    assert String.ends_with?(result.output_path, ".mp4")
    assert File.exists?(result.output_path)
  end

  test "compress/2 rejects unsupported presets" do
    source_path = ImageFixtures.tiny_mp4_path!("compress-source-invalid.mp4")
    output_dir = ImageFixtures.temp_dir!("video-compressor-invalid")

    assert {:error, {:unsupported_preset, "archive"}} =
             VideoCompressor.compress(source_path,
               preset: "archive",
               max_resolution: "720",
               output_dir: output_dir
             )
  end
end
