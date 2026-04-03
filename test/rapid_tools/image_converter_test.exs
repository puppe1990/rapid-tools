defmodule RapidTools.ImageConverterTest do
  use ExUnit.Case, async: true

  alias RapidTools.ImageConverter
  alias RapidTools.TestSupport.ImageFixtures

  test "supported_formats/0 exposes the requested target formats" do
    assert ImageConverter.supported_formats() == ~w(png jpg webp heic avif)
  end

  test "convert/2 converts an image into the target format" do
    source_path = ImageFixtures.tiny_png_path!("source-for-jpg.png")
    output_dir = ImageFixtures.temp_dir!("jpg-conversion")

    assert {:ok, result} = ImageConverter.convert(source_path, "jpg", output_dir: output_dir)
    assert result.target_format == "jpg"
    assert result.media_type == "image/jpeg"
    assert String.ends_with?(result.output_path, ".jpg")
    assert File.exists?(result.output_path)
  end

  test "convert/2 auto-orients images when converting to png" do
    source_path = ImageFixtures.oriented_jpeg_path!("source-oriented.jpg")
    output_dir = ImageFixtures.temp_dir!("png-orientation-conversion")

    assert {:ok, result} = ImageConverter.convert(source_path, "png", output_dir: output_dir)

    assert {identify_output, 0} =
             System.cmd(
               System.find_executable("magick"),
               ["identify", "-format", "%wx%h orientation=%[orientation]", result.output_path],
               stderr_to_stdout: true
             )

    assert identify_output == "30x20 orientation=TopLeft"
  end

  test "convert/2 rejects unsupported target formats" do
    source_path = ImageFixtures.tiny_png_path!("source-for-txt.png")
    output_dir = ImageFixtures.temp_dir!("txt-conversion")

    assert {:error, {:unsupported_target_format, "txt"}} =
             ImageConverter.convert(source_path, "txt", output_dir: output_dir)
  end
end
