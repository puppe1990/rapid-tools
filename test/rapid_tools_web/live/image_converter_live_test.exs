defmodule RapidToolsWeb.ImageConverterLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  test "renders the converter interface", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Tools"
    assert html =~ "Image Converter"
    assert html =~ "Batch image conversion"
    assert html =~ "Image Converter"
    assert html =~ "Convert JPG, PNG, WEBP, HEIC and AVIF"
    assert html =~ "You can select multiple images"
  end

  test "accepts multiple selected images in the upload list", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_png_path!("live-upload-source-1.png")
    source_path_2 = ImageFixtures.tiny_png_path!("live-upload-source-2.png")
    {:ok, view, _html} = live(conn, ~p"/")

    upload =
      file_input(view, "#converter-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "sample-1.png",
          content: File.read!(source_path_1),
          type: "image/png"
        },
        %{
          last_modified: 1_711_000_000_001,
          name: "sample-2.png",
          content: File.read!(source_path_2),
          type: "image/png"
        }
      ])

    rendered_upload = render_upload(upload, "sample-1.png")
    assert rendered_upload =~ "sample-1.png"
    assert rendered_upload =~ "sample-2.png"
  end
end
