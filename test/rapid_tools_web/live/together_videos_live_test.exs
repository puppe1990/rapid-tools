defmodule RapidToolsWeb.TogetherVideosLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  test "renders the together videos interface", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/together-videos")

    assert has_element?(view, "form#together-videos-form")
    assert has_element?(view, "#together-videos-button")
    assert has_element?(view, "#together-videos-upload-list")
    assert has_element?(view, "#together-videos-form .phx-submit-loading\\:flex")
    assert has_element?(view, "a[href=\"/\"]", "Image Converter")
    assert has_element?(view, "a[href=\"/image-resizer\"]", "Image Resizer")
    assert has_element?(view, "a[href=\"/video-converter\"]", "Video Converter")
    assert has_element?(view, "a[href=\"/video-compressor\"]", "Video Compressor")
    assert has_element?(view, "a[href=\"/audio-converter\"]", "Audio Converter")
    assert has_element?(view, "a[href=\"/document-converter\"]", "Document Converter")
    assert has_element?(view, "a[href=\"/together-audios\"]", "Together Audios")
    assert has_element?(view, "a[href=\"/together-videos\"]", "Together Videos")
    assert has_element?(view, "a[href=\"/images-to-video\"]", "Images to Video")
    assert render(view) =~ "Join multiple video files into a single final track."
    assert render(view) =~ "Joining video files"
    assert render(view) =~ "This can take a few seconds."
    assert render(view) =~ "No video selected yet."
    assert render(view) =~ "Reorder the queue with the arrows to define the final track order."
    assert render(view) =~ ~s(value="mp4")
  end

  test "sidebar search input exists", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/together-videos")
    assert has_element?(view, "#tool-search input")
  end

  test "accepts multiple selected videos in the upload list", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_mp4_path!("live-together-video-1.mp4")
    source_path_2 = ImageFixtures.tiny_mp4_path!("live-together-video-2.mp4")
    {:ok, view, _html} = live(conn, ~p"/together-videos")

    upload =
      file_input(view, "#together-videos-form", :video, [
        %{
          last_modified: 1_711_000_000_000,
          name: "sample-1.mp4",
          content: File.read!(source_path_1),
          type: "video/mp4"
        },
        %{
          last_modified: 1_711_000_000_001,
          name: "sample-2.mp4",
          content: File.read!(source_path_2),
          type: "video/mp4"
        }
      ])

    rendered_upload = render_upload(upload, "sample-1.mp4")
    assert rendered_upload =~ "sample-1.mp4"
    assert rendered_upload =~ "sample-2.mp4"
    assert rendered_upload =~ "2 video files in queue. 1/2 finished so far"
    assert rendered_upload =~ "Remove sample-1.mp4"
    assert rendered_upload =~ "phx-click=\"cancel-upload\""
    assert rendered_upload =~ "Move sample-1.mp4 down"
  end

  test "allows reordering uploaded videos before joining", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_mp4_path!("live-together-reorder-video-1.mp4")
    source_path_2 = ImageFixtures.tiny_mp4_path!("live-together-reorder-video-2.mp4")
    {:ok, view, _html} = live(conn, ~p"/together-videos")

    upload =
      file_input(view, "#together-videos-form", :video, [
        %{
          last_modified: 1_711_000_000_002,
          name: "first.mp4",
          content: File.read!(source_path_1),
          type: "video/mp4"
        },
        %{
          last_modified: 1_711_000_000_003,
          name: "second.mp4",
          content: File.read!(source_path_2),
          type: "video/mp4"
        }
      ])

    render_upload(upload, "first.mp4")

    initial_render = render(view)

    assert text_position(initial_render, "first.mp4") <
             text_position(initial_render, "second.mp4")

    reordered_render =
      view
      |> element("button[aria-label=\"Move first.mp4 down\"]")
      |> render_click()

    assert text_position(reordered_render, "second.mp4") <
             text_position(reordered_render, "first.mp4")
  end

  test "shows an explicit initial status message", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/together-videos")

    assert render(view) =~ "Select at least two video files to enable joining."
  end

  defp text_position(rendered, text) do
    case :binary.match(rendered, text) do
      {position, _length} -> position
      :nomatch -> raise "expected to find #{inspect(text)} in rendered output"
    end
  end
end
