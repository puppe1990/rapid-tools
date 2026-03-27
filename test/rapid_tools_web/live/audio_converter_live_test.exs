defmodule RapidToolsWeb.AudioConverterLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  test "renders the audio converter interface", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/audio-converter")

    assert has_element?(view, "form#audio-converter-form")
    assert has_element?(view, "#audio-convert-button")
    assert has_element?(view, "#audio-upload-list")
    assert has_element?(view, "#audio-converter-form .phx-submit-loading\\:flex")
    assert has_element?(view, "a[href=\"/\"]", "Image Converter")
    assert has_element?(view, "a[href=\"/image-resizer\"]", "Image Resizer")
    assert has_element?(view, "a[href=\"/video-converter\"]", "Video Converter")
    assert has_element?(view, "a[href=\"/video-compressor\"]", "Video Compressor")
    assert has_element?(view, "a[href=\"/audio-converter\"]", "Audio Converter")
    assert has_element?(view, "a[href=\"/pdf-converter\"]", "PDF Converter")
    assert has_element?(view, "a[href=\"/together-audios\"]", "Together Audios")
    assert render(view) =~ "Converta arquivos de audio para MP3, WAV, OGG, AAC e FLAC"
    assert render(view) =~ "Convertendo audio"
    assert render(view) =~ "Isso pode levar alguns segundos."
    assert render(view) =~ "Nenhum audio selecionado ainda."
    assert render(view) =~ ~s(value="mp3")
  end

  test "accepts multiple selected audios in the upload list", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_wav_path!("live-upload-audio-1.wav")
    source_path_2 = ImageFixtures.tiny_ogg_path!("live-upload-audio-2.ogg")
    {:ok, view, _html} = live(conn, ~p"/audio-converter")

    upload =
      file_input(view, "#audio-converter-form", :audio, [
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
    {:ok, view, _html} = live(conn, ~p"/audio-converter")

    assert render(view) =~ "Selecione um ou mais audios para habilitar a conversao."
  end
end
