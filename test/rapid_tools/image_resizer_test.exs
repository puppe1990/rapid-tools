defmodule RapidTools.ImageResizerTest do
  use ExUnit.Case, async: true

  alias RapidTools.ImageResizer
  alias RapidTools.TestSupport.ImageFixtures

  test "supported_formats/0 exposes the requested output formats" do
    assert ImageResizer.supported_formats() == ~w(original jpg png webp)
  end

  test "resize/4 resizes an image with a custom target format" do
    source_path = ImageFixtures.tiny_png_path!("resize-source.png")
    output_dir = ImageFixtures.temp_dir!("image-resizer")

    assert {:ok, result} =
             ImageResizer.resize(source_path, 64, 64,
               fit: "contain",
               target_format: "jpg",
               output_dir: output_dir
             )

    assert result.target_format == "jpg"
    assert result.media_type == "image/jpeg"
    assert String.ends_with?(result.output_path, ".jpg")
    assert File.exists?(result.output_path)
  end

  test "resize/4 rejects unsupported target formats" do
    source_path = ImageFixtures.tiny_png_path!("resize-source-invalid.png")
    output_dir = ImageFixtures.temp_dir!("image-resizer-invalid")

    assert {:error, {:unsupported_target_format, "gif"}} =
             ImageResizer.resize(source_path, 64, 64,
               fit: "contain",
               target_format: "gif",
               output_dir: output_dir
             )
  end
end
