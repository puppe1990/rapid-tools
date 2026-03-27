defmodule RapidToolsWeb.ImageResizerLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  test "renders the image resizer interface", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/image-resizer")

    assert has_element?(view, "form#image-resizer-form")
    assert has_element?(view, "#image-resize-button")
    assert has_element?(view, "#image-resizer-upload-list")
    assert has_element?(view, "a[href=\"/image-resizer\"]", "Image Resizer")
    assert html =~ "Resize images in bulk"
    assert html =~ "Instagram Post"
    assert html =~ ~s(value="original")
  end

  test "accepts multiple selected images in the upload list", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_png_path!("resizer-live-1.png")
    source_path_2 = ImageFixtures.tiny_png_path!("resizer-live-2.png")
    {:ok, view, _html} = live(conn, ~p"/image-resizer")

    upload =
      file_input(view, "#image-resizer-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "resize-1.png",
          content: File.read!(source_path_1),
          type: "image/png"
        },
        %{
          last_modified: 1_711_000_000_001,
          name: "resize-2.png",
          content: File.read!(source_path_2),
          type: "image/png"
        }
      ])

    rendered_upload = render_upload(upload, "resize-1.png")
    assert rendered_upload =~ "resize-1.png"
    assert rendered_upload =~ "resize-2.png"
    assert rendered_upload =~ "2 imagens na fila. 1/2 concluidas ate agora"
  end
end
