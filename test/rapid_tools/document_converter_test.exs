defmodule RapidTools.DocumentConverterTest do
  use ExUnit.Case, async: false

  alias RapidTools.DocumentConverter
  alias RapidTools.TestSupport.ImageFixtures

  test "supported_modes/0 exposes all directed pdf md docx pairs when backends are available" do
    with_document_converter_capabilities([extractor: true, soffice: true], fn ->
      modes = DocumentConverter.supported_modes()

      assert "pdf_to_png" in modes
      assert "pdf_to_jpg" in modes
      assert "pdf_to_md_clean" in modes
      assert "pdf_to_md_fidelity" in modes
      assert "pdf_to_docx" in modes
      assert "md_to_pdf" in modes
      assert "md_to_docx" in modes
      assert "docx_to_pdf" in modes
      assert "docx_to_md_clean" in modes
      assert "docx_to_md_fidelity" in modes
      assert "images_to_pdf" in modes
      assert ".docx" in DocumentConverter.accept_extensions()
      assert ".md" in DocumentConverter.accept_extensions()
    end)
  end

  test "reports accepted upload extensions from supported source formats" do
    accepts = DocumentConverter.accept_extensions()

    assert ".pdf" in accepts
    assert ".jpg" in accepts
    assert ".png" in accepts

    if DocumentConverter.supported_mode?("md_to_pdf") do
      assert ".docx" in accepts
      assert ".md" in accepts
    end
  end

  test "omits soffice-backed modes and keeps pdf to docx when soffice is unavailable" do
    with_document_converter_capabilities([extractor: true, soffice: false], fn ->
      modes = DocumentConverter.supported_modes()

      refute "md_to_pdf" in modes
      refute "md_to_docx" in modes
      refute "docx_to_pdf" in modes
      assert "pdf_to_docx" in modes
      refute ".md" in DocumentConverter.accept_extensions()
      assert ".docx" in DocumentConverter.accept_extensions()
      assert "pdf_to_md_clean" in modes
      assert "docx_to_md_clean" in modes
    end)
  end

  test "omits extractor-backed modes when extractor is unavailable" do
    with_document_converter_capabilities([extractor: false, soffice: true], fn ->
      modes = DocumentConverter.supported_modes()

      refute "pdf_to_md_clean" in modes
      refute "pdf_to_md_fidelity" in modes
      refute "pdf_to_docx" in modes
      refute "docx_to_md_clean" in modes
      refute "docx_to_md_fidelity" in modes
      assert "md_to_pdf" in modes
      assert "md_to_docx" in modes
      assert "docx_to_pdf" in modes
      assert ".md" in DocumentConverter.accept_extensions()
      assert ".docx" in DocumentConverter.accept_extensions()
    end)
  end

  test "supports pdf to docx when extractor is available even if soffice is unavailable" do
    with_document_converter_capabilities([extractor: true, soffice: false], fn ->
      modes = DocumentConverter.supported_modes()

      assert "pdf_to_md_clean" in modes
      assert "pdf_to_docx" in modes
      assert DocumentConverter.supported_mode?("pdf_to_docx")
    end)
  end

  test "returns a normal extractor error when extractor-backed conversion is invoked without extractor support" do
    source_dir = ImageFixtures.temp_dir!("document-converter-extractor-error")
    source_path = Path.join(source_dir, "sample.md")
    output_dir = ImageFixtures.temp_dir!("document-converter-extractor-error-output")

    File.write!(source_path, "# Hello\n\nWorld\n")

    with_document_converter_capabilities([extractor: false, soffice: true], fn ->
      assert {:error, :document_extractor_unavailable} =
               DocumentConverter.convert_document_to_markdown(source_path, output_dir, xml: false)
    end)
  end

  test "returns a normal soffice error when office conversion is invoked without soffice support" do
    source_dir = ImageFixtures.temp_dir!("document-converter-soffice-error")
    source_path = Path.join(source_dir, "sample.md")
    output_dir = ImageFixtures.temp_dir!("document-converter-soffice-error-output")

    File.write!(source_path, "# Hello\n\nWorld\n")

    with_document_converter_capabilities([extractor: true, soffice: false], fn ->
      assert {:error, :soffice_not_found} =
               DocumentConverter.convert_office_source_to_target(source_path, output_dir, "pdf")
    end)
  end

  test "normalizes extractor execution errors from markdown conversions" do
    source_path = ImageFixtures.text_pdf_path!("pdf-clean-source.pdf")
    output_dir = ImageFixtures.temp_dir!("document-converter-extractor-runtime-error")

    with_document_converter_capabilities([extractor: true, soffice: false], fn ->
      with_document_converter_runtime_overrides(
        [extract_from_file_result: {:error, "extractor exploded"}],
        fn ->
          assert {:error, {:conversion_failed, "extractor exploded"}} =
                   DocumentConverter.convert(source_path, "pdf_to_md_clean",
                     output_dir: output_dir
                   )
        end
      )
    end)
  end

  test "normalizes soffice execution errors from office conversions" do
    source_dir = ImageFixtures.temp_dir!("document-converter-soffice-runtime-error")
    source_path = Path.join(source_dir, "sample.md")
    output_dir = ImageFixtures.temp_dir!("document-converter-soffice-runtime-error-output")

    File.write!(source_path, "# Hello\n\nWorld\n")

    with_document_converter_capabilities([extractor: false, soffice: true], fn ->
      with_document_converter_runtime_overrides(
        [soffice_command: "fake-soffice", soffice_cmd_result: {"conversion failed", 1}],
        fn ->
          assert {:error, {:conversion_failed, "conversion failed"}} =
                   DocumentConverter.convert(source_path, "md_to_pdf", output_dir: output_dir)
        end
      )
    end)
  end

  test "converts markdown to pdf when soffice is available" do
    if DocumentConverter.supported_mode?("md_to_pdf") do
      source_dir = ImageFixtures.temp_dir!("document-converter-md")
      source_path = Path.join(source_dir, "sample.md")
      output_dir = ImageFixtures.temp_dir!("document-converter-output")

      File.write!(source_path, "# Hello\n\nWorld\n")

      assert {:ok, result} =
               DocumentConverter.convert(source_path, "md_to_pdf", output_dir: output_dir)

      assert File.exists?(result.output_path)
      assert result.media_type == "application/pdf"
      assert result.target_format == "pdf"
    end
  end

  test "converts markdown to docx with list markup preserved in the generated document source" do
    source_dir = ImageFixtures.temp_dir!("document-converter-md-docx")
    source_path = Path.join(source_dir, "sample.md")
    output_dir = ImageFixtures.temp_dir!("document-converter-md-docx-output")
    fake_bin_dir = ImageFixtures.temp_dir!("document-converter-fake-soffice")
    fake_soffice = Path.join(fake_bin_dir, "soffice")

    File.write!(source_path, "# Heading\n\nParagraph\n\n- item one\n- item two\n")
    File.write!(fake_soffice, fake_soffice_script())
    File.chmod!(fake_soffice, 0o755)

    with_document_converter_capabilities([extractor: false, soffice: true], fn ->
      with_document_converter_runtime_overrides([soffice_command: fake_soffice], fn ->
        assert {:ok, result} =
                 DocumentConverter.convert(source_path, "md_to_docx", output_dir: output_dir)

        assert result.media_type ==
                 "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

        assert result.target_format == "docx"
        assert String.ends_with?(result.output_path, ".docx")

        refute File.exists?(Path.join(output_dir, "sample.html"))
        assert File.read!(result.output_path) =~ "<li>item one</li>"
        assert File.read!(result.output_path) =~ "<li>item two</li>"
      end)
    end)
  end

  test "normalizes extractor execution errors from pdf to docx conversions" do
    source_path = ImageFixtures.text_pdf_path!("pdf-to-docx-error-source.pdf")
    output_dir = ImageFixtures.temp_dir!("document-converter-pdf-docx-extractor-runtime-error")

    with_document_converter_capabilities([extractor: true, soffice: false], fn ->
      with_document_converter_runtime_overrides(
        [extract_from_file_result: {:error, "extractor exploded"}],
        fn ->
          assert {:error, {:conversion_failed, "extractor exploded"}} =
                   DocumentConverter.convert(source_path, "pdf_to_docx", output_dir: output_dir)
        end
      )
    end)
  end

  test "returns a conversion error when markdown source cannot be read" do
    source_dir = ImageFixtures.temp_dir!("document-converter-md-unreadable")
    source_path = Path.join(source_dir, "sample.md")
    output_dir = ImageFixtures.temp_dir!("document-converter-md-unreadable-output")
    fake_bin_dir = ImageFixtures.temp_dir!("document-converter-fake-soffice-unreadable")
    fake_soffice = Path.join(fake_bin_dir, "soffice")

    File.write!(source_path, "# Heading\n\nParagraph\n")
    File.write!(fake_soffice, fake_soffice_script())
    File.chmod!(fake_soffice, 0o755)
    File.chmod!(source_path, 0o000)

    with_document_converter_capabilities([extractor: false, soffice: true], fn ->
      with_document_converter_runtime_overrides([soffice_command: fake_soffice], fn ->
        assert {:error, {:conversion_failed, _}} =
                 DocumentConverter.convert(source_path, "md_to_docx", output_dir: output_dir)
      end)
    end)
  end

  test "returns a conversion error when markdown output cannot be written" do
    source_path = ImageFixtures.text_pdf_path!("pdf-clean-source.pdf")
    output_dir = ImageFixtures.temp_dir!("document-converter-md-unwritable-output")
    output_path = Path.join(output_dir, "pdf-clean-source.md")

    File.mkdir_p!(output_dir)
    File.mkdir_p!(output_path)

    with_document_converter_capabilities([extractor: true, soffice: false], fn ->
      assert {:error, {:conversion_failed, _}} =
               DocumentConverter.convert(source_path, "pdf_to_md_clean", output_dir: output_dir)
    end)
  end

  test "converts pdf to markdown in clean mode" do
    source_path = ImageFixtures.text_pdf_path!("pdf-clean-source.pdf")
    output_dir = ImageFixtures.temp_dir!("document-converter-md-clean")

    assert {:ok, result} =
             DocumentConverter.convert(source_path, "pdf_to_md_clean", output_dir: output_dir)

    assert result.media_type == "text/markdown"
    assert result.target_format == "md"
    assert String.ends_with?(result.output_path, ".md")

    markdown = File.read!(result.output_path)
    assert markdown =~ "Rapid Tools PDF Title"
    assert markdown =~ "First paragraph for markdown extraction."
  end

  test "converts pdf to markdown in fidelity mode" do
    source_path = ImageFixtures.text_pdf_path!("pdf-fidelity-source.pdf")
    output_dir = ImageFixtures.temp_dir!("document-converter-md-fidelity")

    assert {:ok, result} =
             DocumentConverter.convert(source_path, "pdf_to_md_fidelity", output_dir: output_dir)

    assert result.media_type == "text/markdown"
    assert result.target_format == "md"

    markdown = File.read!(result.output_path)
    assert markdown =~ "# Page 1"
    assert markdown =~ "Rapid Tools PDF Title"
  end

  test "converts pdf to docx as a real docx package with extracted content" do
    source_path = ImageFixtures.text_pdf_path!("pdf-to-docx-source.pdf")
    output_dir = ImageFixtures.temp_dir!("document-converter-pdf-docx")

    with_document_converter_capabilities([extractor: true, soffice: false], fn ->
      assert {:ok, result} =
               DocumentConverter.convert(source_path, "pdf_to_docx", output_dir: output_dir)

      assert result.media_type ==
               "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

      assert result.target_format == "docx"
      assert String.ends_with?(result.output_path, ".docx")
      assert File.exists?(result.output_path)

      {:ok, entries} = :zip.extract(String.to_charlist(result.output_path), [:memory])

      entries =
        Map.new(entries, fn {path, contents} ->
          {List.to_string(path), IO.iodata_to_binary(contents)}
        end)

      assert Map.has_key?(entries, "[Content_Types].xml")
      assert Map.has_key?(entries, "_rels/.rels")
      assert Map.has_key?(entries, "word/document.xml")

      assert_valid_xml_part!(entries["[Content_Types].xml"])
      assert_valid_xml_part!(entries["_rels/.rels"])
      assert_valid_xml_part!(entries["word/document.xml"])

      assert entries["word/document.xml"] =~ "Rapid Tools PDF Title"
      assert entries["word/document.xml"] =~ "First paragraph for markdown extraction."
      assert entries["word/document.xml"] =~ "one"
      assert entries["word/document.xml"] =~ "two"
      refute entries["word/document.xml"] =~ "Heading1"
      refute entries["word/document.xml"] =~ "ListParagraph"
    end)
  end

  test "converts docx to markdown in clean mode" do
    source_path = ImageFixtures.docx_path!("docx-clean-source.docx")
    output_dir = ImageFixtures.temp_dir!("document-converter-docx-clean")

    assert {:ok, result} =
             DocumentConverter.convert(source_path, "docx_to_md_clean", output_dir: output_dir)

    assert result.media_type == "text/markdown"
    assert result.target_format == "md"

    markdown = File.read!(result.output_path)
    assert markdown =~ "Rapid Tools DOCX Title"
    assert markdown =~ "First paragraph for markdown extraction."
    assert markdown =~ "Bullet one"
    assert markdown =~ "Bullet two"
  end

  test "converts docx to markdown in fidelity mode" do
    source_path = ImageFixtures.docx_path!("docx-fidelity-source.docx")
    output_dir = ImageFixtures.temp_dir!("document-converter-docx-fidelity")

    assert {:ok, result} =
             DocumentConverter.convert(source_path, "docx_to_md_fidelity", output_dir: output_dir)

    assert result.media_type == "text/markdown"
    assert result.target_format == "md"

    markdown = File.read!(result.output_path)
    refute markdown =~ "# Page 1"
    assert markdown =~ "Rapid Tools DOCX Title"
    assert markdown =~ "First paragraph for markdown extraction."
  end

  test "converts docx to pdf" do
    source_path = ImageFixtures.docx_path!("docx-pdf-source.docx")
    output_dir = ImageFixtures.temp_dir!("document-converter-docx-pdf")
    fake_bin_dir = ImageFixtures.temp_dir!("document-converter-fake-soffice-docx")
    fake_soffice = Path.join(fake_bin_dir, "soffice")

    File.write!(fake_soffice, fake_soffice_script())
    File.chmod!(fake_soffice, 0o755)

    with_document_converter_capabilities([extractor: true, soffice: true], fn ->
      with_document_converter_runtime_overrides(
        [soffice_command: fake_soffice],
        fn ->
          assert {:ok, result} =
                   DocumentConverter.convert(source_path, "docx_to_pdf", output_dir: output_dir)

          assert result.media_type == "application/pdf"
          assert result.target_format == "pdf"
          assert String.ends_with?(result.output_path, ".pdf")
          assert File.exists?(result.output_path)
        end
      )
    end)
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

  defp with_document_converter_runtime_overrides(opts, fun) do
    original = Application.get_env(:rapid_tools, :document_converter_runtime_overrides)

    Application.put_env(:rapid_tools, :document_converter_runtime_overrides, Enum.into(opts, %{}))

    try do
      fun.()
    after
      if is_nil(original) do
        Application.delete_env(:rapid_tools, :document_converter_runtime_overrides)
      else
        Application.put_env(:rapid_tools, :document_converter_runtime_overrides, original)
      end
    end
  end

  defp fake_soffice_script do
    """
    #!/bin/sh
    set -eu

    outdir=""
    target=""
    input=""

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --outdir)
          outdir="$2"
          shift 2
          ;;
        --convert-to)
          target="$2"
          shift 2
          ;;
        --headless)
          shift
          ;;
        *)
          input="$1"
          shift
          ;;
      esac
    done

    basename=$(basename "$input")
    filename="${basename%.*}.${target}"
    cp "$input" "$outdir/$filename"
    """
  end

  defp assert_valid_xml_part!(xml) do
    assert String.starts_with?(xml, "<?xml")

    assert {{:xmlElement, _, _, _, _, _, _, _, _, _, _, _}, []} =
             :xmerl_scan.string(to_charlist(xml))
  end
end
