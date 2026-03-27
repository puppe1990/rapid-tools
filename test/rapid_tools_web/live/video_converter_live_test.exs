defmodule RapidToolsWeb.VideoConverterLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  test "renders the video converter interface", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    assert has_element?(view, "form#video-converter-form")
    assert has_element?(view, "#video-convert-button")
    assert has_element?(view, "#video-converter-form .phx-submit-loading\\:flex")
    assert has_element?(view, "a[href=\"/\"]", "Image Converter")
    assert has_element?(view, "a[href=\"/video-converter\"]", "Video Converter")
    assert has_element?(view, "a[href=\"/audio-converter\"]", "Audio Converter")
    assert render(view) =~ "Converta videos para MP4, MOV, WEBM, MKV e AVI"
    assert render(view) =~ "Convertendo video"
    assert render(view) =~ "Isso pode levar alguns segundos."
    assert render(view) =~ ~s(value="mp4")
  end

  test "accepts multiple selected videos in the upload list", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_mp4_path!("live-upload-video-1.mp4")
    source_path_2 = ImageFixtures.tiny_mp4_path!("live-upload-video-2.mp4")
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    upload =
      file_input(view, "#video-converter-form", :video, [
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
  end
end
