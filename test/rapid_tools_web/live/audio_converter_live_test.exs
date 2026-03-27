defmodule RapidToolsWeb.AudioConverterLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  test "renders the audio converter interface", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/audio-converter")

    assert has_element?(view, "form#audio-converter-form")
    assert has_element?(view, "#audio-convert-button")
    assert has_element?(view, "#audio-converter-form .phx-submit-loading\\:flex")
    assert has_element?(view, "a[href=\"/\"]", "Image Converter")
    assert has_element?(view, "a[href=\"/video-converter\"]", "Video Converter")
    assert has_element?(view, "a[href=\"/audio-converter\"]", "Audio Converter")
    assert render(view) =~ "Converta arquivos de audio para MP3, WAV, OGG, AAC e FLAC"
    assert render(view) =~ "Convertendo audio"
    assert render(view) =~ "Isso pode levar alguns segundos."
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
  end
end
