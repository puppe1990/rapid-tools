defmodule RapidToolsWeb.ImagesToVideoLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  test "renders the converter interface", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/images-to-video")

    assert has_element?(view, "form#images-to-video-form")
    assert has_element?(view, "#images-to-video-button")
    assert has_element?(view, "#images-to-video-upload-list")
    assert has_element?(view, "a[href=\"/images-to-video\"]", "Images to Video")
    assert html =~ "Images to Video"
    assert html =~ "Turn your photos into a video or animated GIF"
    assert html =~ ~s(value="mp4")
  end

  test "accepts multiple selected images in the upload list", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_png_path!("live-upload-source-1.png")
    source_path_2 = ImageFixtures.tiny_png_path!("live-upload-source-2.png")

    {:ok, view, _html} = live(conn, ~p"/images-to-video")

    upload =
      file_input(view, "#images-to-video-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "frame-1.png",
          content: File.read!(source_path_1),
          type: "image/png"
        },
        %{
          last_modified: 1_711_000_000_001,
          name: "frame-2.png",
          content: File.read!(source_path_2),
          type: "image/png"
        }
      ])

    rendered_upload = render_upload(upload, "frame-1.png")
    assert rendered_upload =~ "frame-1.png"
    assert rendered_upload =~ "frame-2.png"
    assert rendered_upload =~ "2 images in queue. 1/2 finished so far"
  end

  test "reorders images with move up and move down", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_png_path!("reorder-1.png")
    source_path_2 = ImageFixtures.tiny_png_path!("reorder-2.png")

    {:ok, view, _html} = live(conn, ~p"/images-to-video")

    upload =
      file_input(view, "#images-to-video-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "first.png",
          content: File.read!(source_path_1),
          type: "image/png"
        },
        %{
          last_modified: 1_711_000_000_001,
          name: "second.png",
          content: File.read!(source_path_2),
          type: "image/png"
        }
      ])

    render_upload(upload, "first.png")

    html =
      view
      |> element("button[phx-click='move-down']")
      |> render_click()

    assert html =~ "second.png"
    assert html =~ "first.png"
  end

  test "generates an mp4 from uploaded images", %{conn: conn} do
    source_path = ImageFixtures.tiny_png_path!("mp4-frame-1.png")

    {:ok, view, _html} = live(conn, ~p"/images-to-video")

    upload =
      file_input(view, "#images-to-video-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "frame-1.png",
          content: File.read!(source_path),
          type: "image/png"
        }
      ])

    render_upload(upload, "frame-1.png")

    view
    |> form("#images-to-video-form",
      conversion: %{target_format: "mp4", interval: "1"}
    )
    |> render_submit()

    assert has_element?(view, "#images-to-video-result")
    assert has_element?(view, "a[download]", "Download MP4")
  end

  test "generates a gif from uploaded images", %{conn: conn} do
    source_path = ImageFixtures.tiny_png_path!("gif-frame-1.png")

    {:ok, view, _html} = live(conn, ~p"/images-to-video")

    upload =
      file_input(view, "#images-to-video-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "frame-1.png",
          content: File.read!(source_path),
          type: "image/png"
        }
      ])

    render_upload(upload, "frame-1.png")

    view
    |> form("#images-to-video-form",
      conversion: %{target_format: "gif", interval: "1"}
    )
    |> render_submit()

    assert has_element?(view, "#images-to-video-result")
    assert has_element?(view, "a[download]", "Download GIF")
  end

  test "shows error when submitting without images", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/images-to-video")

    html =
      view
      |> form("#images-to-video-form", conversion: %{target_format: "mp4", interval: "2"})
      |> render_submit()

    assert html =~ "Select at least one image"
  end

  test "cancelling an upload removes it from the list", %{conn: conn} do
    source_path = ImageFixtures.tiny_png_path!("cancel-frame.png")

    {:ok, view, _html} = live(conn, ~p"/images-to-video")

    upload =
      file_input(view, "#images-to-video-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "cancel-me.png",
          content: File.read!(source_path),
          type: "image/png"
        }
      ])

    render_upload(upload, "cancel-me.png")

    assert has_element?(view, "#images-to-video-upload-list", "cancel-me.png")

    view
    |> element("button[phx-click='cancel-upload']")
    |> render_click()

    refute has_element?(view, "#images-to-video-upload-list", "cancel-me.png")
  end
end
