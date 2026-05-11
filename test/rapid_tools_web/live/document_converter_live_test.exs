defmodule RapidToolsWeb.DocumentConverterLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  test "renders the document converter interface", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/document-converter")

    assert has_element?(view, "form#document-converter-form")
    assert has_element?(view, "#document-convert-button")
    assert has_element?(view, "#document-upload-list")
    assert has_element?(view, "a[href=\"/document-converter\"]", "Document Converter")
    assert html =~ "Document workflow"
    assert html =~ "Convert PDFs, documents and text files"
    assert html =~ "PDF to Markdown (Clean)"
    assert html =~ "PDF to Markdown (Fidelity)"
  end

  test "renders the primary pdf md docx roundtrip modes when the runtime supports them", %{
    conn: conn
  } do
    with_document_converter_capabilities([extractor: true, soffice: true], fn ->
      {:ok, _view, html} = live(conn, ~p"/document-converter")

      assert html =~ "PDF to DOCX"
      assert html =~ "Markdown to PDF"
      assert html =~ "Markdown to DOCX"
      assert html =~ "DOCX to PDF"
      assert html =~ "DOCX to Markdown (Clean)"
      assert html =~ "DOCX to Markdown (Fidelity)"
      assert html =~ "PDF to Markdown (Clean)"
      assert html =~ "PDF to Markdown (Fidelity)"
      assert html =~ "PDF to PNG"
      assert html =~ "PDF to JPG"
      assert html =~ "Images to PDF"
    end)
  end

  test "hides extractor-backed modes and shows the unavailable extractor card when only soffice is available",
       %{conn: conn} do
    with_document_converter_capabilities([extractor: false, soffice: true], fn ->
      {:ok, _view, html} = live(conn, ~p"/document-converter")

      refute has_element?(_view, "option[value=\"pdf_to_docx\"]")
      refute has_element?(_view, "option[value=\"pdf_to_md_clean\"]")
      refute has_element?(_view, "option[value=\"pdf_to_md_fidelity\"]")
      refute has_element?(_view, "option[value=\"docx_to_md_clean\"]")
      refute has_element?(_view, "option[value=\"docx_to_md_fidelity\"]")

      assert has_element?(_view, "option[value=\"md_to_pdf\"]")
      assert has_element?(_view, "option[value=\"md_to_docx\"]")
      assert has_element?(_view, "option[value=\"docx_to_pdf\"]")
      assert html =~ "PDF extraction modes are unavailable"

      assert html =~
               "Install the document extractor to enable PDF to Markdown (Clean), PDF to Markdown (Fidelity) and PDF to DOCX."
    end)
  end

  test "shows extractor-backed modes and hides office-only modes when only the extractor is available",
       %{conn: conn} do
    with_document_converter_capabilities([extractor: true, soffice: false], fn ->
      {:ok, view, html} = live(conn, ~p"/document-converter")

      assert has_element?(view, "option[value=\"pdf_to_docx\"]")
      assert has_element?(view, "option[value=\"pdf_to_md_clean\"]")
      assert has_element?(view, "option[value=\"pdf_to_md_fidelity\"]")
      assert has_element?(view, "option[value=\"docx_to_md_clean\"]")
      assert has_element?(view, "option[value=\"docx_to_md_fidelity\"]")

      refute has_element?(view, "option[value=\"md_to_pdf\"]")
      refute has_element?(view, "option[value=\"md_to_docx\"]")
      refute has_element?(view, "option[value=\"docx_to_pdf\"]")

      assert html =~ "Unlock office document modes"

      assert html =~
               "Install a working LibreOffice on the server to enable Markdown to PDF, Markdown to DOCX and DOCX to PDF."
    end)
  end

  test "hides office modes and shows the unavailable extractor and office cards when neither backend is available",
       %{conn: conn} do
    with_document_converter_capabilities([extractor: false, soffice: false], fn ->
      {:ok, _view, html} = live(conn, ~p"/document-converter")

      refute has_element?(_view, "option[value=\"pdf_to_docx\"]")
      refute has_element?(_view, "option[value=\"pdf_to_md_clean\"]")
      refute has_element?(_view, "option[value=\"pdf_to_md_fidelity\"]")
      refute has_element?(_view, "option[value=\"md_to_pdf\"]")
      refute has_element?(_view, "option[value=\"md_to_docx\"]")
      refute has_element?(_view, "option[value=\"docx_to_pdf\"]")
      refute has_element?(_view, "option[value=\"docx_to_md_clean\"]")
      refute has_element?(_view, "option[value=\"docx_to_md_fidelity\"]")

      assert html =~ "PDF extraction modes are unavailable"
      assert html =~ "Unlock office document modes"
    end)
  end

  test "accepts a selected PDF in the upload list", %{conn: conn} do
    source_path = ImageFixtures.tiny_pdf_path!("document-live-source.pdf")
    {:ok, view, _html} = live(conn, ~p"/document-converter")

    upload =
      file_input(view, "#document-converter-form", :document, [
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

  defp with_document_converter_capabilities(opts, fun) do
    original = Application.get_env(:rapid_tools, :document_converter_capabilities)

    Application.put_env(:rapid_tools, :document_converter_capabilities, %{
      extractor: Keyword.fetch!(opts, :extractor),
      soffice: Keyword.fetch!(opts, :soffice)
    })

    try do
      fun.()
    after
      if is_nil(original) do
        Application.delete_env(:rapid_tools, :document_converter_capabilities)
      else
        Application.put_env(:rapid_tools, :document_converter_capabilities, original)
      end
    end
  end
end
