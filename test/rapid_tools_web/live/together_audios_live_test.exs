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
    assert has_element?(view, "a[href=\"/video-converter\"]", "Video Converter")
    assert has_element?(view, "a[href=\"/audio-converter\"]", "Audio Converter")
    assert has_element?(view, "a[href=\"/together-audios\"]", "Together Audios")
    assert render(view) =~ "Junte varios arquivos de audio em uma unica faixa final."
    assert render(view) =~ "Unindo audios"
    assert render(view) =~ "Isso pode levar alguns segundos."
    assert render(view) =~ "Nenhum audio selecionado ainda."
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
  end

  test "shows an explicit initial status message", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/together-audios")

    assert render(view) =~ "Selecione pelo menos dois audios para habilitar a uniao."
  end
end
