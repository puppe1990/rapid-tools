defmodule RapidTools.DocumentConverter.DocxWriter do
  @moduledoc false

  @doc_type "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

  def write_markdown(markdown, source_path, output_dir) do
    basename = Path.rootname(Path.basename(source_path))
    output_path = Path.join(output_dir, "#{basename}.docx")

    File.rm(output_path)

    case :zip.create(String.to_charlist(output_path), docx_entries(markdown), []) do
      {:ok, _zip_path} ->
        {:ok,
         %{
           output_path: output_path,
           filename: Path.basename(output_path),
           media_type: @doc_type,
           target_format: "docx"
         }}

      {:error, reason} ->
        {:error, {:conversion_failed, reason}}
    end
  end

  defp docx_entries(markdown) do
    [
      {~c"[Content_Types].xml", content_types_xml()},
      {~c"_rels/.rels", package_rels_xml()},
      {~c"word/document.xml", document_xml(markdown)}
    ]
  end

  defp document_xml(markdown) do
    body =
      markdown
      |> normalized_blocks()
      |> Enum.flat_map(&block_to_paragraphs/1)
      |> case do
        [] -> [paragraph_xml("")]
        paragraphs -> paragraphs
      end
      |> Enum.join("")

    [
      ~s(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>),
      ~s(<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">),
      ~s(<w:body>),
      body,
      ~s(<w:sectPr><w:pgSz w:w="12240" w:h="15840"/></w:sectPr>),
      ~s(</w:body>),
      ~s(</w:document>)
    ]
    |> IO.iodata_to_binary()
  end

  defp normalized_blocks(markdown) do
    markdown
    |> String.replace("\r\n", "\n")
    |> String.trim()
    |> case do
      "" -> []
      text -> String.split(text, ~r/\n{2,}/, trim: true)
    end
  end

  defp block_to_paragraphs("# " <> rest), do: [paragraph_xml(rest)]
  defp block_to_paragraphs("## " <> rest), do: [paragraph_xml(rest)]
  defp block_to_paragraphs("### " <> rest), do: [paragraph_xml(rest)]

  defp block_to_paragraphs(block) do
    case list_items(block) do
      [] ->
        [paragraph_xml(join_lines(block))]

      items ->
        Enum.map(items, &paragraph_xml/1)
    end
  end

  defp join_lines(block) do
    block
    |> String.split("\n", trim: true)
    |> Enum.map_join(" ", &String.trim/1)
  end

  defp list_items(block) do
    lines = String.split(block, "\n", trim: true)

    if Enum.all?(lines, &list_item_line?/1) do
      Enum.map(lines, &list_item_text/1)
    else
      []
    end
  end

  defp list_item_line?(line) do
    trimmed = String.trim_leading(line)

    String.starts_with?(trimmed, "- ") or String.starts_with?(trimmed, "* ")
  end

  defp list_item_text(line) do
    line
    |> String.trim_leading()
    |> String.replace_prefix("- ", "")
    |> String.replace_prefix("* ", "")
    |> String.trim()
  end

  defp paragraph_xml(text) do
    [
      ~s(<w:p><w:r><w:t>),
      xml_escape(text),
      ~s(</w:t></w:r></w:p>)
    ]
    |> IO.iodata_to_binary()
  end

  defp xml_escape(text) do
    text
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp content_types_xml do
    [
      ~s(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>),
      ~s(<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">),
      ~s(<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>),
      ~s(<Default Extension="xml" ContentType="application/xml"/>),
      ~s(<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>),
      ~s(</Types>)
    ]
    |> IO.iodata_to_binary()
  end

  defp package_rels_xml do
    [
      ~s(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>),
      ~s(<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">),
      ~s(<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>),
      ~s(</Relationships>)
    ]
    |> IO.iodata_to_binary()
  end
end
