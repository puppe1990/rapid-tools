defmodule RapidTools.ImagesToVideoConverterTest do
  use ExUnit.Case, async: false

  alias RapidTools.ImagesToVideoConverter
  alias RapidTools.TestSupport.ImageFixtures

  describe "supported_formats/0" do
    test "returns mp4 and gif" do
      assert ImagesToVideoConverter.supported_formats() == ~w(mp4 gif)
    end
  end

  describe "convert/3" do
    setup do
      dir = ImageFixtures.temp_dir!("images-to-video-test")
      image_1 = ImageFixtures.tiny_png_path!("frame-1.png")
      image_2 = ImageFixtures.tiny_png_path!("frame-2.png")
      image_3 = ImageFixtures.tiny_png_path!("frame-3.png")

      {:ok, dir: dir, image_1: image_1, image_2: image_2, image_3: image_3}
    end

    test "creates an mp4 from multiple images with default interval", %{
      dir: dir,
      image_1: image_1,
      image_2: image_2
    } do
      assert {:ok, result} =
               ImagesToVideoConverter.convert([image_1, image_2], "mp4", output_dir: dir)

      assert result.filename == "images-to-video.mp4"
      assert result.media_type == "video/mp4"
      assert result.target_format == "mp4"
      assert File.exists?(result.output_path)
      assert File.stat!(result.output_path).size > 0
    end

    test "creates a gif from multiple images with default interval", %{
      dir: dir,
      image_1: image_1,
      image_2: image_2
    } do
      assert {:ok, result} =
               ImagesToVideoConverter.convert([image_1, image_2], "gif", output_dir: dir)

      assert result.filename == "images-to-video.gif"
      assert result.media_type == "image/gif"
      assert result.target_format == "gif"
      assert File.exists?(result.output_path)
      assert File.stat!(result.output_path).size > 0
    end

    test "creates an mp4 with a custom interval", %{
      dir: dir,
      image_1: image_1,
      image_2: image_2,
      image_3: image_3
    } do
      assert {:ok, result} =
               ImagesToVideoConverter.convert([image_1, image_2, image_3], "mp4",
                 output_dir: dir,
                 interval: 1
               )

      assert result.target_format == "mp4"
      assert File.exists?(result.output_path)
    end

    test "returns error when no images are provided", %{dir: dir} do
      assert {:error, :not_enough_source_files} =
               ImagesToVideoConverter.convert([], "mp4", output_dir: dir)
    end

    test "returns error for unsupported target format", %{dir: dir, image_1: image_1} do
      assert {:error, {:unsupported_target_format, "avi"}} =
               ImagesToVideoConverter.convert([image_1], "avi", output_dir: dir)
    end

    test "returns error when a source file is missing", %{dir: dir} do
      assert {:error, :source_file_not_found} =
               ImagesToVideoConverter.convert(["/nonexistent.png"], "mp4", output_dir: dir)
    end

    test "creates an mp4 from mixed formats and sizes", %{dir: dir} do
      png_32 = ImageFixtures.sized_png_path!("frame-32.png", 32, 32)
      png_64 = ImageFixtures.sized_png_path!("frame-64.png", 64, 64)
      webp_48 = ImageFixtures.sized_webp_path!("frame-48.webp", 48, 48)

      assert {:ok, result} =
               ImagesToVideoConverter.convert([png_32, webp_48, png_64], "mp4",
                 output_dir: dir,
                 interval: 1
               )

      assert result.target_format == "mp4"
      assert File.exists?(result.output_path)

      # Verify duration is at least ~2.5s (3 frames x 1s - some encoding tolerance)
      ffprobe = System.find_executable("ffprobe")
      assert ffprobe != nil

      {output, 0} =
        System.cmd(
          ffprobe,
          [
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            result.output_path
          ],
          stderr_to_stdout: true
        )

      duration = output |> String.trim() |> String.to_float()
      assert duration >= 2.5
    end
  end
end
