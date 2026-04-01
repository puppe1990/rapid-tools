defmodule RapidToolsWeb.VideoConverterLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  test "renders the video converter interface", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    assert has_element?(view, "form#video-converter-form")
    assert has_element?(view, "#video-convert-button")
    assert has_element?(view, "#video-upload-list")
    assert has_element?(view, "#video-converter-form .phx-submit-loading\\:flex")
    assert has_element?(view, "a[href=\"/\"]", "Image Converter")
    assert has_element?(view, "a[href=\"/image-resizer\"]", "Image Resizer")
    assert has_element?(view, "a[href=\"/video-converter\"]", "Video Converter")
    assert has_element?(view, "a[href=\"/video-compressor\"]", "Video Compressor")
    assert has_element?(view, "a[href=\"/audio-converter\"]", "Audio Converter")
    assert has_element?(view, "a[href=\"/pdf-converter\"]", "PDF Converter")
    assert has_element?(view, "a[href=\"/together-audios\"]", "Together Audios")
    assert render(view) =~ "Converta videos para MP4, MOV, WEBM, MKV e AVI"
    assert render(view) =~ "Convertendo video"
    assert render(view) =~ "Isso pode levar alguns segundos."
    assert render(view) =~ "Nenhum video selecionado ainda."
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
    assert rendered_upload =~ "2 videos na fila. 1/2 concluidos ate agora"
    assert rendered_upload =~ "Remover sample-1.mp4"
    assert rendered_upload =~ "phx-click=\"cancel-upload\""
  end

  test "accepts webm uploads even when the browser falls back to application/octet-stream", %{
    conn: conn
  } do
    source_path = ImageFixtures.tiny_mp4_path!("live-upload-video-webm.mp4")
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    upload =
      file_input(view, "#video-converter-form", :video, [
        %{
          last_modified: 1_711_000_000_002,
          name: "recording.webm",
          content: File.read!(source_path),
          type: "application/octet-stream"
        }
      ])

    rendered_upload = render_upload(upload, "recording.webm")
    assert rendered_upload =~ "recording.webm"
    assert rendered_upload =~ "pronto"
    refute rendered_upload =~ "Formato nao aceito"
  end

  test "shows an explicit initial status message", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    assert render(view) =~ "Selecione um ou mais videos para habilitar a conversao."
  end

  test "shows a specific error flash instead of crashing when media is invalid", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    upload =
      file_input(view, "#video-converter-form", :video, [
        %{
          last_modified: 1_711_000_000_003,
          name: "broken.mp4",
          content: "not-a-real-video",
          type: "video/mp4"
        }
      ])

    assert render_upload(upload, "broken.mp4") =~ "broken.mp4"

    html =
      view
      |> form("#video-converter-form", conversion: %{target_format: "mp4"})
      |> render_submit()

    assert html =~ "Este arquivo parece corrompido ou incompleto."
  end

  test "shows a specific error for mp4 files without a video track", %{conn: conn} do
    source_path = ImageFixtures.audio_only_mp4_path!("audio-only-upload.mp4")
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    upload =
      file_input(view, "#video-converter-form", :video, [
        %{
          last_modified: 1_711_000_000_004,
          name: "audio-only.mp4",
          content: File.read!(source_path),
          type: "video/mp4"
        }
      ])

    assert render_upload(upload, "audio-only.mp4") =~ "audio-only.mp4"

    html =
      view
      |> form("#video-converter-form", conversion: %{target_format: "webm"})
      |> render_submit()

    assert html =~ "Este arquivo nao possui uma trilha de video."
  end
end
