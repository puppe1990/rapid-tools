defmodule RapidTools.AudioJoinerTest do
  use ExUnit.Case, async: true

  alias RapidTools.AudioJoiner
  alias RapidTools.TestSupport.ImageFixtures

  test "join/3 concatenates multiple audio files into a single output" do
    first_source = ImageFixtures.tiny_wav_path!("join-source-1.wav")
    second_source = ImageFixtures.tiny_wav_path!("join-source-2.wav")
    output_dir = ImageFixtures.temp_dir!("audio-join")

    assert {:ok, result} =
             AudioJoiner.join([first_source, second_source], "mp3", output_dir: output_dir)

    assert result.target_format == "mp3"
    assert result.media_type == "audio/mpeg"
    assert result.filename == "together-audios.mp3"
    assert String.ends_with?(result.output_path, "/together-audios.mp3")
    assert File.exists?(result.output_path)
  end

  test "join/3 rejects fewer than two audio files" do
    source_path = ImageFixtures.tiny_wav_path!("join-single-source.wav")
    output_dir = ImageFixtures.temp_dir!("audio-join-single")

    assert {:error, :not_enough_source_files} =
             AudioJoiner.join([source_path], "mp3", output_dir: output_dir)
  end
end
