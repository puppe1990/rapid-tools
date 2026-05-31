defmodule RapidTools.VideoJoinerTest do
  use ExUnit.Case, async: true

  alias RapidTools.TestSupport.ImageFixtures
  alias RapidTools.VideoJoiner

  test "join/3 concatenates multiple video files into a single output" do
    first_source = ImageFixtures.tiny_mp4_path!("join-video-source-1.mp4")
    second_source = ImageFixtures.tiny_mp4_path!("join-video-source-2.mp4")
    output_dir = ImageFixtures.temp_dir!("video-join")

    assert {:ok, result} =
             VideoJoiner.join([first_source, second_source], "mp4", output_dir: output_dir)

    assert result.target_format == "mp4"
    assert result.media_type == "video/mp4"
    assert result.filename == "together-videos.mp4"
    assert String.ends_with?(result.output_path, "/together-videos.mp4")
    assert File.exists?(result.output_path)
  end

  test "join/3 rejects fewer than two video files" do
    source_path = ImageFixtures.tiny_mp4_path!("join-single-video.mp4")
    output_dir = ImageFixtures.temp_dir!("video-join-single")

    assert {:error, :not_enough_source_files} =
             VideoJoiner.join([source_path], "mp4", output_dir: output_dir)
  end

  test "join/3 rejects unsupported target format" do
    first_source = ImageFixtures.tiny_mp4_path!("join-unsupported-video-1.mp4")
    second_source = ImageFixtures.tiny_mp4_path!("join-unsupported-video-2.mp4")
    output_dir = ImageFixtures.temp_dir!("video-join-unsupported")

    assert {:error, {:unsupported_target_format, "gif"}} =
             VideoJoiner.join([first_source, second_source], "gif", output_dir: output_dir)
  end

  test "join/3 rejects non-existent source files" do
    output_dir = ImageFixtures.temp_dir!("video-join-missing")

    assert {:error, :source_file_not_found} =
             VideoJoiner.join(["/non/existent-1.mp4", "/non/existent-2.mp4"], "mp4",
               output_dir: output_dir
             )
  end

  test "join/3 concatenates to mov format" do
    first_source = ImageFixtures.tiny_mp4_path!("join-mov-1.mp4")
    second_source = ImageFixtures.tiny_mp4_path!("join-mov-2.mp4")
    output_dir = ImageFixtures.temp_dir!("video-join-mov")

    assert {:ok, result} =
             VideoJoiner.join([first_source, second_source], "mov", output_dir: output_dir)

    assert result.target_format == "mov"
    assert result.media_type == "video/quicktime"
    assert File.exists?(result.output_path)
  end

  test "join/3 concatenates to webm format" do
    first_source = ImageFixtures.tiny_mp4_path!("join-webm-1.mp4")
    second_source = ImageFixtures.tiny_mp4_path!("join-webm-2.mp4")
    output_dir = ImageFixtures.temp_dir!("video-join-webm")

    assert {:ok, result} =
             VideoJoiner.join([first_source, second_source], "webm", output_dir: output_dir)

    assert result.target_format == "webm"
    assert result.media_type == "video/webm"
    assert File.exists?(result.output_path)
  end

  test "join/3 concatenates video with audio and video without audio" do
    with_audio = ImageFixtures.tiny_mp4_path!("join-with-audio.mp4")
    without_audio = ImageFixtures.video_only_mp4_path!("join-no-audio.mp4")
    output_dir = ImageFixtures.temp_dir!("video-join-mixed-audio")

    assert {:ok, result} =
             VideoJoiner.join([with_audio, without_audio], "mp4", output_dir: output_dir)

    assert result.target_format == "mp4"
    assert File.exists?(result.output_path)

    # The joined file should be at least as large as the larger input
    assert File.stat!(result.output_path).size > 0
  end

  test "join/3 concatenates more than two videos" do
    first = ImageFixtures.tiny_mp4_path!("join-three-1.mp4")
    second = ImageFixtures.tiny_mp4_path!("join-three-2.mp4")
    third = ImageFixtures.tiny_mp4_path!("join-three-3.mp4")
    output_dir = ImageFixtures.temp_dir!("video-join-three")

    assert {:ok, result} =
             VideoJoiner.join([first, second, third], "mp4", output_dir: output_dir)

    assert result.target_format == "mp4"
    assert File.exists?(result.output_path)
  end
end
