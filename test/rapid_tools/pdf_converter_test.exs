defmodule RapidTools.PdfConverterTest do
  use ExUnit.Case, async: true

  alias RapidTools.PdfConverter
  alias RapidTools.TestSupport.ImageFixtures

  test "supported_modes/0 exposes both PDF workflows" do
    assert PdfConverter.supported_modes() == ~w(pdf_to_png pdf_to_jpg images_to_pdf)
  end

  test "pdf_to_images/3 converts a PDF page into PNG" do
    source_path = ImageFixtures.tiny_pdf_path!("pdf-to-png-source.pdf")
    output_dir = ImageFixtures.temp_dir!("pdf-to-png")

    assert {:ok, [result]} =
             PdfConverter.pdf_to_images(source_path, "png", output_dir: output_dir)

    assert result.target_format == "png"
    assert result.media_type == "image/png"
    assert String.ends_with?(result.output_path, ".png")
    assert File.exists?(result.output_path)
  end

  test "images_to_pdf/2 combines images into a PDF" do
    source_path_1 = ImageFixtures.tiny_png_path!("images-to-pdf-1.png")
    source_path_2 = ImageFixtures.tiny_png_path!("images-to-pdf-2.png")
    output_dir = ImageFixtures.temp_dir!("images-to-pdf")

    assert {:ok, result} =
             PdfConverter.images_to_pdf([source_path_1, source_path_2], output_dir: output_dir)

    assert result.media_type == "application/pdf"
    assert String.ends_with?(result.output_path, ".pdf")
    assert File.exists?(result.output_path)
  end
end
