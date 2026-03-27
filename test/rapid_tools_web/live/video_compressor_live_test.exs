defmodule RapidToolsWeb.VideoCompressorLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  test "renders the video compressor interface", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/video-compressor")

    assert has_element?(view, "form#video-compressor-form")
    assert has_element?(view, "#video-compress-button")
    assert has_element?(view, "#video-compressor-upload-list")
    assert has_element?(view, "a[href=\"/video-compressor\"]", "Video Compressor")
    assert html =~ "Compress videos for sharing"
    assert html =~ "Small size"
    assert html =~ ~s(value="balanced")
  end

  test "accepts multiple selected videos in the upload list", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_mp4_path!("compress-live-1.mp4")
    source_path_2 = ImageFixtures.tiny_mp4_path!("compress-live-2.mp4")
    {:ok, view, _html} = live(conn, ~p"/video-compressor")

    upload =
      file_input(view, "#video-compressor-form", :video, [
        %{
          last_modified: 1_711_000_000_000,
          name: "compress-1.mp4",
          content: File.read!(source_path_1),
          type: "video/mp4"
        },
        %{
          last_modified: 1_711_000_000_001,
          name: "compress-2.mp4",
          content: File.read!(source_path_2),
          type: "video/mp4"
        }
      ])

    rendered_upload = render_upload(upload, "compress-1.mp4")
    assert rendered_upload =~ "compress-1.mp4"
    assert rendered_upload =~ "compress-2.mp4"
    assert rendered_upload =~ "2 videos na fila. 1/2 concluidos ate agora"
  end
end
