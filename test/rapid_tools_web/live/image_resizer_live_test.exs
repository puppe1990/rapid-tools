defmodule RapidToolsWeb.ImageResizerLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  defp eventually_render_including(view, expected, attempts \\ 20)

  defp eventually_render_including(view, _expected, 1), do: render(view)

  defp eventually_render_including(view, expected, attempts) do
    html = render(view)

    if html =~ expected do
      html
    else
      Process.sleep(50)
      eventually_render_including(view, expected, attempts - 1)
    end
  end

  test "renders the image resizer interface", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/image-resizer")

    assert has_element?(view, "form#image-resizer-form")
    assert has_element?(view, "#image-resize-button")
    assert has_element?(view, "#image-resizer-upload-list")
    assert has_element?(view, "a[href=\"/image-resizer\"]", "Image Resizer")
    assert html =~ "Resize images in bulk"
    assert html =~ "Instagram Post"
    assert html =~ ~s(value="original")
    assert html =~ "40 MB"
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
    assert rendered_upload =~ "2 images in queue. 1/2 finished so far"
  end

  test "resizes uploaded images asynchronously without crashing", %{conn: conn} do
    source_path = ImageFixtures.tiny_png_path!("resizer-async-source.png")
    {:ok, view, _html} = live(conn, ~p"/image-resizer")

    upload =
      file_input(view, "#image-resizer-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "async-resize.png",
          content: File.read!(source_path),
          type: "image/png"
        }
      ])

    render_upload(upload, "async-resize.png")

    view
    |> form("#image-resizer-form",
      resize: %{
        preset: "custom",
        width: "64",
        height: "64",
        fit: "contain",
        target_format: "jpg"
      }
    )
    |> render_submit()

    html = eventually_render_including(view, "resized-results")
    assert html =~ "async-resize-64x64.jpg" or html =~ "images ready"
    assert has_element?(view, "#resized-results")
  end

  test "uses typed dimensions even when a named preset is still selected", %{conn: conn} do
    source_path = ImageFixtures.tiny_png_path!("resizer-custom-dims.png")
    {:ok, view, _html} = live(conn, ~p"/image-resizer")

    upload =
      file_input(view, "#image-resizer-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "product.png",
          content: File.read!(source_path),
          type: "image/png"
        }
      ])

    render_upload(upload, "product.png")

    # Same situation as the bug report: Instagram Post selected, but user typed 400x400.
    view
    |> form("#image-resizer-form",
      resize: %{
        preset: "instagram_post",
        width: "400",
        height: "400",
        fit: "cover",
        target_format: "original"
      }
    )
    |> render_submit()

    html = eventually_render_including(view, "resized-results")
    assert html =~ "product-400x400.png"
    assert html =~ "400 x 400"
    refute html =~ "1080 x 1080"
  end

  test "switching preset fills the matching dimensions", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/image-resizer")

    html =
      view
      |> form("#image-resizer-form",
        resize: %{
          preset: "instagram_story",
          width: "1080",
          height: "1080",
          fit: "contain",
          target_format: "original"
        }
      )
      |> render_change(%{"_target" => ["resize", "preset"]})

    assert html =~ ~s(value="1080")
    assert html =~ ~s(value="1920")
    assert html =~ ~s(value="instagram_story")
  end

  test "editing width while a named preset is selected switches to custom", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/image-resizer")

    html =
      view
      |> form("#image-resizer-form",
        resize: %{
          preset: "instagram_post",
          width: "400",
          height: "1080",
          fit: "cover",
          target_format: "original"
        }
      )
      |> render_change(%{"_target" => ["resize", "width"]})

    assert html =~ ~s(value="custom")
    assert html =~ ~s(value="400")
  end

  test "surfaces not-accepted upload errors instead of appearing stuck", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/image-resizer")

    upload =
      file_input(view, "#image-resizer-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "notes.txt",
          content: "not an image",
          type: "text/plain"
        }
      ])

    assert {:error, [[_ref, :not_accepted]]} = render_upload(upload, "notes.txt")

    html = render(view)
    assert html =~ "notes.txt"
    assert html =~ "Format not accepted"
  end
end
