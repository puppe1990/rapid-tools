defmodule RapidTools.TestSupport.ImageFixtures do
  @moduledoc false

  def tiny_png_path!(name \\ "tiny.png") do
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)
    command = System.find_executable("magick") || System.find_executable("convert")

    case command do
      nil ->
        raise "ImageMagick is required to build test fixtures"

      _ ->
        {_, 0} = System.cmd(command, ["-size", "2x2", "xc:#4f46e5", path], stderr_to_stdout: true)
    end

    path
  end

  def temp_dir!(name) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "rapid_tools_tests/#{name}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end

  def tiny_mp4_path!(name \\ "tiny.mp4") do
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)

    case System.find_executable("ffmpeg") do
      nil ->
        raise "ffmpeg is required to build video test fixtures"

      command ->
        {_, 0} =
          System.cmd(
            command,
            [
              "-y",
              "-f",
              "lavfi",
              "-i",
              "color=c=#0ea5e9:s=32x32:d=1",
              "-f",
              "lavfi",
              "-i",
              "anullsrc=channel_layout=stereo:sample_rate=44100",
              "-shortest",
              "-c:v",
              "libx264",
              "-pix_fmt",
              "yuv420p",
              "-c:a",
              "aac",
              path
            ],
            stderr_to_stdout: true
          )
    end

    path
  end

  def tiny_wav_path!(name \\ "tiny.wav") do
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)

    case System.find_executable("ffmpeg") do
      nil ->
        raise "ffmpeg is required to build audio test fixtures"

      command ->
        {_, 0} =
          System.cmd(
            command,
            [
              "-y",
              "-f",
              "lavfi",
              "-i",
              "sine=frequency=880:duration=1",
              "-c:a",
              "pcm_s16le",
              path
            ],
            stderr_to_stdout: true
          )
    end

    path
  end

  def tiny_ogg_path!(name \\ "tiny.ogg") do
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)

    case System.find_executable("ffmpeg") do
      nil ->
        raise "ffmpeg is required to build audio test fixtures"

      command ->
        {_, 0} =
          System.cmd(
            command,
            [
              "-y",
              "-f",
              "lavfi",
              "-i",
              "sine=frequency=660:duration=1",
              "-c:a",
              "libvorbis",
              path
            ],
            stderr_to_stdout: true
          )
    end

    path
  end
end
