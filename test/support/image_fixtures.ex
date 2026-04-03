defmodule RapidTools.TestSupport.ImageFixtures do
  @moduledoc false

  @oriented_jpeg_base64 """
  /9j/4AAQSkZJRgABAQEASABIAAD/4QBiRXhpZgAATU0AKgAAAAgABQESAAMAAAABAAYAAAEaAAUAAAABAAAASgEbAAUAAAABAAAAUgEoAAMAAAABAAIAAAITAAMAAAABAAEAAAAAAAAAAABIAAAAAQAAAEgAAAAB/9sAQwAJBgYIBgUJCAcICgkJCg0WDg0MDA0aExQQFh8cISAfHB4eIycyKiMlLyUeHis7LC8zNTg4OCEqPUE8NkEyNzg1/9sAQwEJCgoNCw0ZDg4ZNSQeJDU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1/8AAEQgAHgAUAwEiAAIRAQMRAf/EABkAAAMBAQEAAAAAAAAAAAAAAAAGBwUDBP/EACoQAAICAQMDAgUFAAAAAAAAAAECAwQRAAUhBhIxE2EHFEGBsRUiUZGi/8QAFgEBAQEAAAAAAAAAAAAAAAAAAwQA/8QAGREAAgMBAAAAAAAAAAAAAAAAAQMAAhEh/9oADAMBAAIRAxEAPwBcufDq9Y3Q/p3y8jRc+mX/AHMuThu0jwfbIyNcN36L6gkoJHLU5AUHsYZ4++m/rujNY6Xr3qbTRWqAGXjYjKEnPI/g86wa/U3U2z3IEuWVnp+krsZgGJB9/Ofvqhqq1tkFbLGuxOm6R3NJO0VSgHgFlz+dGqHvG47fvsle4oEDGAK6FfDAtnHto04SvIBczeCO70BLstqrKvqn5cBlH14bP51Ma9SWzVrQJGrmQrGgGe4ZGB9vp/WqdBMy0pnzljBIP851O3cR7ZXKEqXWPBXgg86zwTyZZA7MRq0kMjokx7Qx4B8aNeG/uEgtEoBhgGOTjzzo1J2UAz//2Q==
  """

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

  def oriented_jpeg_path!(name \\ "oriented.jpg") do
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)

    binary =
      @oriented_jpeg_base64
      |> String.replace(~r/\s+/, "")
      |> Base.decode64!()

    File.write!(path, binary)
    path
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

  def audio_only_mp4_path!(name \\ "audio-only.mp4") do
    source_path = tiny_wav_path!("#{Path.rootname(name)}.wav")
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)

    case System.find_executable("ffmpeg") do
      nil ->
        raise "ffmpeg is required to build audio-only mp4 test fixtures"

      command ->
        {_, 0} =
          System.cmd(
            command,
            [
              "-y",
              "-i",
              source_path,
              "-c:a",
              "aac",
              "-vn",
              path
            ],
            stderr_to_stdout: true
          )
    end

    path
  end

  def tiny_pdf_path!(name \\ "tiny.pdf") do
    png_path = tiny_png_path!("#{Path.rootname(name)}.png")
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)
    command = System.find_executable("magick") || System.find_executable("convert")

    case command do
      nil ->
        raise "ImageMagick is required to build PDF test fixtures"

      _ ->
        {_, 0} = System.cmd(command, [png_path, path], stderr_to_stdout: true)
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
