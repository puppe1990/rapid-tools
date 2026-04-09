defmodule RapidToolsWeb.PdfConverterLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  test "renders the PDF converter interface", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/pdf-converter")

    assert has_element?(view, "form#pdf-converter-form")
    assert has_element?(view, "#pdf-convert-button")
    assert has_element?(view, "#pdf-upload-list")
    assert has_element?(view, "a[href=\"/pdf-converter\"]", "PDF Converter")
    assert html =~ "Convert PDFs and images"
    assert html =~ "PDF to PNG"
    assert html =~ ~s(value="pdf_to_png")
  end

  test "accepts a selected PDF in the upload list", %{conn: conn} do
    source_path = ImageFixtures.tiny_pdf_path!("pdf-live-source.pdf")
    {:ok, view, _html} = live(conn, ~p"/pdf-converter")

    upload =
      file_input(view, "#pdf-converter-form", :document, [
        %{
          last_modified: 1_711_000_000_000,
          name: "sample.pdf",
          content: File.read!(source_path),
          type: "application/pdf"
        }
      ])

    rendered_upload = render_upload(upload, "sample.pdf")
    assert rendered_upload =~ "sample.pdf"
    assert rendered_upload =~ "1 files in queue. 1/1 finished so far."
  end
end
