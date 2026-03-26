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
end
