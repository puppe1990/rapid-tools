defmodule RapidToolsWeb.ImageConverterLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  test "renders the converter interface", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert has_element?(view, "form#converter-form")
    assert has_element?(view, "#image-convert-button")
    assert has_element?(view, "#image-upload-list")
    assert has_element?(view, "#converter-form .phx-submit-loading\\:flex")
    assert has_element?(view, "a[href=\"/\"]", "Image Converter")
    assert has_element?(view, "a[href=\"/image-resizer\"]", "Image Resizer")
    assert has_element?(view, "a[href=\"/video-converter\"]", "Video Converter")
    assert has_element?(view, "a[href=\"/video-compressor\"]", "Video Compressor")
    assert has_element?(view, "a[href=\"/audio-converter\"]", "Audio Converter")
    assert has_element?(view, "a[href=\"/pdf-converter\"]", "PDF Converter")
    assert has_element?(view, "a[href=\"/together-audios\"]", "Together Audios")
    assert html =~ "Tools"
    assert html =~ "Image Converter"
    assert html =~ "Image workflow"
    assert html =~ "Converta imagens para PNG, JPG, WEBP, HEIC e AVIF"

    assert html =~
             "Ideal para exportar assets para web, social, aplicativos e bibliotecas de design."

    assert html =~ "Convertendo imagens"
    assert html =~ "Isso pode levar alguns segundos."
    assert html =~ ~s(value="png")
  end

  test "accepts multiple selected images in the upload list", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_png_path!("live-upload-source-1.png")
    source_path_2 = ImageFixtures.tiny_png_path!("live-upload-source-2.png")
    {:ok, view, _html} = live(conn, ~p"/")

    upload =
      file_input(view, "#converter-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "sample-1.png",
          content: File.read!(source_path_1),
          type: "image/png"
        },
        %{
          last_modified: 1_711_000_000_001,
          name: "sample-2.png",
          content: File.read!(source_path_2),
          type: "image/png"
        }
      ])

    rendered_upload = render_upload(upload, "sample-1.png")
    assert rendered_upload =~ "sample-1.png"
    assert rendered_upload =~ "sample-2.png"
    assert rendered_upload =~ "2 imagens na fila. 1/2 concluidas ate agora"
  end

  test "clearing uploads keeps converted results intact", %{conn: conn} do
    source_path = ImageFixtures.tiny_png_path!("live-clear-uploads-source.png")
    {:ok, view, _html} = live(conn, ~p"/")

    upload =
      file_input(view, "#converter-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "converted-source.png",
          content: File.read!(source_path),
          type: "image/png"
        }
      ])

    render_upload(upload, "converted-source.png")

    view
    |> form("#converter-form", conversion: %{target_format: "jpg"})
    |> render_submit()

    assert has_element?(view, "#converted-results")
    assert has_element?(view, "#clear-converted-results")

    pending_upload =
      file_input(view, "#converter-form", :image, [
        %{
          last_modified: 1_711_000_000_001,
          name: "pending-source.png",
          content: File.read!(source_path),
          type: "image/png"
        }
      ])

    render_upload(pending_upload, "pending-source.png")

    assert has_element?(view, "#image-upload-list", "pending-source.png")

    view
    |> element("#clear-upload-list")
    |> render_click()

    refute has_element?(view, "#image-upload-list", "pending-source.png")
    assert has_element?(view, "#converted-results")
  end

  test "clearing converted results keeps uploaded images intact", %{conn: conn} do
    source_path = ImageFixtures.tiny_png_path!("live-clear-results-source.png")
    {:ok, view, _html} = live(conn, ~p"/")

    upload =
      file_input(view, "#converter-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "converted-source.png",
          content: File.read!(source_path),
          type: "image/png"
        }
      ])

    render_upload(upload, "converted-source.png")

    view
    |> form("#converter-form", conversion: %{target_format: "jpg"})
    |> render_submit()

    assert has_element?(view, "#converted-results")
    assert has_element?(view, "#clear-converted-results")

    queued_upload =
      file_input(view, "#converter-form", :image, [
        %{
          last_modified: 1_711_000_000_001,
          name: "queued-source.png",
          content: File.read!(source_path),
          type: "image/png"
        }
      ])

    render_upload(queued_upload, "queued-source.png")

    assert has_element?(view, "#image-upload-list", "queued-source.png")

    view
    |> element("#clear-converted-results")
    |> render_click()

    refute has_element?(view, "#converted-results")
    assert has_element?(view, "#image-upload-list", "queued-source.png")
  end
end
