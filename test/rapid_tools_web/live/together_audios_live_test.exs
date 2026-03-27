defmodule RapidToolsWeb.TogetherAudiosLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  test "renders the together audios interface", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/together-audios")

    assert has_element?(view, "form#together-audios-form")
    assert has_element?(view, "#together-audios-button")
    assert has_element?(view, "#together-audios-upload-list")
    assert has_element?(view, "#together-audios-form .phx-submit-loading\\:flex")
    assert has_element?(view, "a[href=\"/\"]", "Image Converter")
    assert has_element?(view, "a[href=\"/image-resizer\"]", "Image Resizer")
    assert has_element?(view, "a[href=\"/video-converter\"]", "Video Converter")
    assert has_element?(view, "a[href=\"/video-compressor\"]", "Video Compressor")
    assert has_element?(view, "a[href=\"/audio-converter\"]", "Audio Converter")
    assert has_element?(view, "a[href=\"/pdf-converter\"]", "PDF Converter")
    assert has_element?(view, "a[href=\"/together-audios\"]", "Together Audios")
    assert render(view) =~ "Junte varios arquivos de audio em uma unica faixa final."
    assert render(view) =~ "Unindo audios"
    assert render(view) =~ "Isso pode levar alguns segundos."
    assert render(view) =~ "Nenhum audio selecionado ainda."
    assert render(view) =~ "Reordene a fila com as setas para definir a sequencia final da faixa."
    assert render(view) =~ ~s(value="mp3")
  end

  test "accepts multiple selected audios in the upload list", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_wav_path!("live-together-audio-1.wav")
    source_path_2 = ImageFixtures.tiny_ogg_path!("live-together-audio-2.ogg")
    {:ok, view, _html} = live(conn, ~p"/together-audios")

    upload =
      file_input(view, "#together-audios-form", :audio, [
        %{
          last_modified: 1_711_000_000_000,
          name: "sample-1.wav",
          content: File.read!(source_path_1),
          type: "audio/wav"
        },
        %{
          last_modified: 1_711_000_000_001,
          name: "sample-2.ogg",
          content: File.read!(source_path_2),
          type: "audio/ogg"
        }
      ])

    rendered_upload = render_upload(upload, "sample-1.wav")
    assert rendered_upload =~ "sample-1.wav"
    assert rendered_upload =~ "sample-2.ogg"
    assert rendered_upload =~ "2 audios na fila. 1/2 concluidos ate agora"
    assert rendered_upload =~ "Remover sample-1.wav"
    assert rendered_upload =~ "phx-click=\"cancel-upload\""
    assert rendered_upload =~ "Mover sample-1.wav para baixo"
  end

  test "allows reordering uploaded audios before joining", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_wav_path!("live-together-reorder-1.wav")
    source_path_2 = ImageFixtures.tiny_ogg_path!("live-together-reorder-2.ogg")
    {:ok, view, _html} = live(conn, ~p"/together-audios")

    upload =
      file_input(view, "#together-audios-form", :audio, [
        %{
          last_modified: 1_711_000_000_002,
          name: "first.wav",
          content: File.read!(source_path_1),
          type: "audio/wav"
        },
        %{
          last_modified: 1_711_000_000_003,
          name: "second.ogg",
          content: File.read!(source_path_2),
          type: "audio/ogg"
        }
      ])

    render_upload(upload, "first.wav")

    initial_render = render(view)

    assert text_position(initial_render, "first.wav") <
             text_position(initial_render, "second.ogg")

    reordered_render =
      view
      |> element("button[aria-label=\"Mover first.wav para baixo\"]")
      |> render_click()

    assert text_position(reordered_render, "second.ogg") <
             text_position(reordered_render, "first.wav")
  end

  test "shows an explicit initial status message", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/together-audios")

    assert render(view) =~ "Selecione pelo menos dois audios para habilitar a uniao."
  end

  defp text_position(rendered, text) do
    case :binary.match(rendered, text) do
      {position, _length} -> position
      :nomatch -> raise "expected to find #{inspect(text)} in rendered output"
    end
  end
end
