defmodule RapidToolsWeb.ExtractAudioLiveTest do
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

  test "renders the extract audio interface", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/extract-audio")

    assert has_element?(view, "form#extract-audio-form")
    assert has_element?(view, "#extract-audio-button")
    assert has_element?(view, "#extract-audio-upload-list")
    assert has_element?(view, "a[href=\"/extract-audio\"]", "Extract Audio")
    assert render(view) =~ "Extraia o audio de videos em MP3, WAV, OGG, AAC e FLAC"
    assert render(view) =~ "Extraindo audio"
    assert render(view) =~ "Nenhum video selecionado ainda."
    assert render(view) =~ ~s(value="mp3")
  end

  test "accepts uploaded videos in the queue", %{conn: conn} do
    source_path = ImageFixtures.tiny_mp4_path!("extract-audio-upload.mp4")
    {:ok, view, _html} = live(conn, ~p"/extract-audio")

    upload =
      file_input(view, "#extract-audio-form", :video, [
        %{
          last_modified: 1_711_000_000_100,
          name: "clip.mp4",
          content: File.read!(source_path),
          type: "video/mp4"
        }
      ])

    rendered_upload = render_upload(upload, "clip.mp4")
    assert rendered_upload =~ "clip.mp4"
    assert rendered_upload =~ "pronto"
    refute rendered_upload =~ "Formato nao aceito"
  end

  test "shows a specific error for videos without an audio track", %{conn: conn} do
    source_path = ImageFixtures.video_only_mp4_path!("video-only-upload.mp4")
    {:ok, view, _html} = live(conn, ~p"/extract-audio")

    upload =
      file_input(view, "#extract-audio-form", :video, [
        %{
          last_modified: 1_711_000_000_101,
          name: "video-only.mp4",
          content: File.read!(source_path),
          type: "video/mp4"
        }
      ])

    assert render_upload(upload, "video-only.mp4") =~ "video-only.mp4"

    _html =
      view
      |> form("#extract-audio-form", conversion: %{target_format: "mp3"})
      |> render_submit()

    html = eventually_render_including(view, "Este video nao possui uma trilha de audio.")
    assert html =~ "Este video nao possui uma trilha de audio."
  end
end
