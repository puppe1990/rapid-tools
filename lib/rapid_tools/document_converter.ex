defmodule RapidTools.DocumentConverter do
  @moduledoc false

  alias RapidTools.DocumentConverter.DocxWriter
  alias RapidTools.PdfConverter

  @pdf_modes ~w(pdf_to_png pdf_to_jpg images_to_pdf)
  @pdf_markdown_modes ~w(pdf_to_md_clean pdf_to_md_fidelity)
  @pdf_docx_modes ~w(pdf_to_docx)
  @office_pdf_modes ~w(docx_to_pdf odt_to_pdf rtf_to_pdf txt_to_pdf md_to_pdf html_to_pdf)
  @office_docx_modes ~w(md_to_docx)
  @docx_markdown_modes ~w(docx_to_md_clean docx_to_md_fidelity)

  def supported_modes do
    capabilities = runtime_capabilities()

    @pdf_modes ++
      pdf_markdown_modes(capabilities) ++
      pdf_docx_modes(capabilities) ++
      office_pdf_modes(capabilities) ++
      office_docx_modes(capabilities) ++
      docx_markdown_modes(capabilities)
  end

  def accept_extensions do
    supported_modes()
    |> Enum.flat_map(&source_extensions_for_mode/1)
    |> Enum.uniq()
  end

  def supported_mode?(mode) do
    normalize_value(mode) in supported_modes()
  end

  def source_extensions_for_mode(mode) do
    mode
    |> normalize_value()
    |> source_extensions_for_normalized_mode()
  end

  defp source_extensions_for_normalized_mode("pdf_to_png"), do: [".pdf"]
  defp source_extensions_for_normalized_mode("pdf_to_jpg"), do: [".pdf"]
  defp source_extensions_for_normalized_mode("pdf_to_md_clean"), do: [".pdf"]
  defp source_extensions_for_normalized_mode("pdf_to_md_fidelity"), do: [".pdf"]
  defp source_extensions_for_normalized_mode("pdf_to_docx"), do: [".pdf"]

  defp source_extensions_for_normalized_mode("images_to_pdf"),
    do: [".jpg", ".jpeg", ".png", ".webp"]

  defp source_extensions_for_normalized_mode(mode) when mode in @office_pdf_modes do
    [".#{mode |> String.split("_to_") |> hd()}"]
  end

  defp source_extensions_for_normalized_mode("md_to_docx"), do: [".md"]
  defp source_extensions_for_normalized_mode("docx_to_md_clean"), do: [".docx"]
  defp source_extensions_for_normalized_mode("docx_to_md_fidelity"), do: [".docx"]
  defp source_extensions_for_normalized_mode(_), do: []

  def convert(source_path, mode, opts \\ []) do
    mode = normalize_value(mode)

    with :ok <- validate_mode(mode),
         :ok <- ensure_source_exists(source_path),
         :ok <- validate_source_extension(source_path, mode),
         {:ok, output_dir} <- ensure_output_dir(opts) do
      do_convert(source_path, mode, output_dir)
    end
  end

  def combine_as_pdf(source_paths, opts \\ []) when is_list(source_paths) do
    PdfConverter.images_to_pdf(source_paths, opts)
  end

  defp do_convert(source_path, "pdf_to_png", output_dir) do
    PdfConverter.pdf_to_images(source_path, "png", output_dir: output_dir)
  end

  defp do_convert(source_path, "pdf_to_jpg", output_dir) do
    PdfConverter.pdf_to_images(source_path, "jpg", output_dir: output_dir)
  end

  defp do_convert(source_path, "pdf_to_md_clean", output_dir) do
    convert_document_to_markdown(source_path, output_dir, xml: false)
  end

  defp do_convert(source_path, "pdf_to_md_fidelity", output_dir) do
    convert_document_to_markdown(source_path, output_dir, xml: true)
  end

  defp do_convert(source_path, "pdf_to_docx", output_dir) do
    case extract_document_content(source_path, xml: false) do
      {:ok, %{content: content}} ->
        markdown =
          markdown_from_document_result(content, false, source_extension(source_path))

        DocxWriter.write_markdown(markdown, source_path, output_dir)

      {:error, reason} ->
        {:error, {:conversion_failed, reason}}
    end
  end

  defp do_convert(source_path, "md_to_pdf", output_dir) do
    convert_markdown_file_to_office(source_path, output_dir, "pdf")
  end

  defp do_convert(source_path, "md_to_docx", output_dir) do
    convert_markdown_file_to_office(source_path, output_dir, "docx")
  end

  defp do_convert(source_path, mode, output_dir) when mode in @office_pdf_modes do
    convert_office_source_to_target(source_path, output_dir, "pdf")
  end

  defp do_convert(source_path, "docx_to_md_clean", output_dir) do
    convert_document_to_markdown(source_path, output_dir, xml: false)
  end

  defp do_convert(source_path, "docx_to_md_fidelity", output_dir) do
    convert_document_to_markdown(source_path, output_dir, xml: true)
  end

  defp validate_mode(mode) do
    if supported_mode?(mode), do: :ok, else: {:error, {:unsupported_mode, mode}}
  end

  defp validate_source_extension(source_path, mode) do
    if source_extension(source_path) in source_extensions_for_mode(mode) do
      :ok
    else
      {:error, {:unsupported_source_format, source_extension(source_path), mode}}
    end
  end

  defp ensure_source_exists(source_path) do
    if File.exists?(source_path), do: :ok, else: {:error, :source_file_not_found}
  end

  defp ensure_output_dir(opts) do
    output_dir = Keyword.get(opts, :output_dir, default_output_dir())

    case File.mkdir_p(output_dir) do
      :ok -> {:ok, output_dir}
      {:error, reason} -> {:error, {:output_dir_error, reason}}
    end
  end

  defp runtime_capabilities do
    override = Application.get_env(:rapid_tools, :document_converter_capabilities, %{})

    %{
      extractor: capability_value(override, :extractor, &probe_extractor_available?/0),
      soffice: capability_value(override, :soffice, &probe_soffice_available?/0)
    }
  end

  defp capability_value(override, key, probe_fun) do
    case override do
      %{^key => value} when is_boolean(value) ->
        value

      %{"extractor" => value} when key == :extractor and is_boolean(value) ->
        value

      %{"soffice" => value} when key == :soffice and is_boolean(value) ->
        value

      _ ->
        probe_fun.()
    end
  end

  defp office_pdf_modes(%{soffice: true}), do: @office_pdf_modes
  defp office_pdf_modes(_), do: []

  defp pdf_markdown_modes(%{extractor: true}), do: @pdf_markdown_modes
  defp pdf_markdown_modes(_), do: []

  defp pdf_docx_modes(%{extractor: true}), do: @pdf_docx_modes
  defp pdf_docx_modes(_), do: []

  defp office_docx_modes(%{soffice: true}), do: @office_docx_modes
  defp office_docx_modes(_), do: []

  defp docx_markdown_modes(%{extractor: true}), do: @docx_markdown_modes
  defp docx_markdown_modes(_), do: []

  defp probe_extractor_available? do
    if Code.ensure_loaded?(ExtractousEx) and
         function_exported?(ExtractousEx, :extract_from_file, 2) do
      extractor_probe_path =
        Path.join(
          System.tmp_dir!(),
          "rapid_tools_document_converter_probe-#{System.unique_integer([:positive])}.txt"
        )

      try do
        File.write!(extractor_probe_path, "probe")

        case ExtractousEx.extract_from_file(extractor_probe_path) do
          {:ok, %{content: content}} when is_binary(content) ->
            String.trim(content) != ""

          _ ->
            false
        end
      after
        File.rm(extractor_probe_path)
      end
    else
      false
    end
  rescue
    _ -> false
  end

  defp probe_soffice_available? do
    case soffice_command() do
      nil -> false
      _ -> true
    end
  end

  defp soffice_command do
    case soffice_command_override() do
      command when is_binary(command) and command != "" ->
        command

      _ ->
        probe_soffice_command()
    end
  end

  defp probe_soffice_command do
    case System.find_executable("soffice") do
      nil -> nil
      soffice -> if soffice_version_ok?(soffice), do: soffice, else: nil
    end
  end

  defp soffice_version_ok?(soffice) do
    case System.cmd(soffice, ["--version"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp soffice_command_override do
    case runtime_test_overrides() do
      %{soffice_command: command} ->
        command

      %{"soffice_command" => command} ->
        command

      _ ->
        nil
    end
  end

  defp markdown_html_source(source_path, output_dir) do
    html_path = Path.join(output_dir, "#{Path.rootname(Path.basename(source_path))}.html")

    with {:ok, markdown} <- File.read(source_path),
         :ok <- File.write(html_path, markdown_to_html(markdown)) do
      {:ok, html_path}
    else
      {:error, reason} -> {:error, {:conversion_failed, reason}}
    end
  end

  defp convert_markdown_file_to_office(source_path, output_dir, target_format) do
    with {:ok, html_path} <- markdown_html_source(source_path, output_dir) do
      try do
        case soffice_convert_to_target(html_path, output_dir, target_format) do
          {:ok, output_path} ->
            {:ok,
             %{
               output_path: output_path,
               filename: Path.basename(output_path),
               media_type: office_media_type(target_format),
               target_format: target_format
             }}

          {:error, _} = error ->
            error
        end
      after
        File.rm(html_path)
      end
    end
  end

  @doc false
  def convert_office_source_to_target(source_path, output_dir, target_format) do
    case soffice_convert_to_target(source_path, output_dir, target_format) do
      {:ok, output_path} ->
        {:ok,
         %{
           output_path: output_path,
           filename: Path.basename(output_path),
           media_type: office_media_type(target_format),
           target_format: target_format
         }}

      {:error, _} = error ->
        error
    end
  end

  defp markdown_to_html(markdown) do
    body =
      markdown
      |> String.split(~r/\n{2,}/, trim: true)
      |> Enum.map_join("\n", &markdown_block_to_html/1)

    """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>RapidTools document</title>
      <style>
        body { font-family: Helvetica, Arial, sans-serif; padding: 32px; color: #0f172a; }
        h1, h2, h3 { margin: 0 0 12px; }
        p { margin: 0 0 12px; line-height: 1.5; }
      </style>
    </head>
    <body>
    #{body}
    </body>
    </html>
    """
  end

  defp markdown_block_to_html("# " <> rest), do: "<h1>#{html_escape(rest)}</h1>"
  defp markdown_block_to_html("## " <> rest), do: "<h2>#{html_escape(rest)}</h2>"
  defp markdown_block_to_html("### " <> rest), do: "<h3>#{html_escape(rest)}</h3>"

  defp markdown_block_to_html(block) do
    case list_items_from_markdown_block(block) do
      [] ->
        block
        |> String.split("\n", trim: true)
        |> Enum.map_join("<br />", &html_escape/1)
        |> then(&"<p>#{&1}</p>")

      items ->
        items
        |> Enum.map_join("", &"<li>#{html_escape(&1)}</li>")
        |> then(&"<ul>#{&1}</ul>")
    end
  end

  defp list_items_from_markdown_block(block) do
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

  defp html_escape(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp source_extension(source_path) do
    source_path
    |> Path.extname()
    |> String.downcase()
  end

  defp normalize_value(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp default_output_dir do
    Path.join(System.tmp_dir!(), "rapid_tools_document_conversions")
  end

  @doc false
  def convert_document_to_markdown(source_path, output_dir, opts \\ []) do
    if runtime_capabilities().extractor do
      extract_opts = Keyword.take(opts, [:xml])

      case extract_document_content(source_path, extract_opts) do
        {:ok, result} ->
          markdown =
            markdown_from_document_result(
              result.content,
              Keyword.get(opts, :xml, false),
              source_extension(source_path)
            )

          build_markdown_result(source_path, output_dir, markdown)

        {:error, reason} ->
          {:error, {:conversion_failed, reason}}
      end
    else
      {:error, :document_extractor_unavailable}
    end
  end

  defp markdown_from_document_result(content, true, ".docx"),
    do: docx_fidelity_markdown_from_structured_content(content)

  defp markdown_from_document_result(content, true, _extension),
    do: fidelity_markdown_from_structured_content(content)

  defp markdown_from_document_result(content, false, _extension),
    do: clean_markdown_from_text(content)

  defp build_markdown_result(source_path, output_dir, markdown) do
    output_path = Path.join(output_dir, "#{Path.rootname(Path.basename(source_path))}.md")

    case File.write(output_path, markdown) do
      :ok ->
        {:ok,
         %{
           output_path: output_path,
           filename: Path.basename(output_path),
           media_type: "text/markdown",
           target_format: "md"
         }}

      {:error, reason} ->
        {:error, {:conversion_failed, reason}}
    end
  end

  defp clean_markdown_from_text(content) do
    content
    |> String.replace("\r\n", "\n")
    |> String.replace(~r/[ \t]+/, " ")
    |> String.split(~r/\n{2,}/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index()
    |> Enum.map_join("\n\n", fn
      {block, 0} -> "# " <> block
      {<<"Bullet ", rest::binary>>, _} -> "- " <> rest
      {block, _} -> block |> String.split("\n", trim: true) |> Enum.join(" ")
    end)
    |> Kernel.<>("\n")
  end

  defp fidelity_markdown_from_structured_content(content) do
    body =
      content
      |> strip_xml_tags()
      |> String.replace("\r\n", "\n")
      |> String.split(~r/\n{2,}/, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.with_index()
      |> Enum.map_join("\n\n", fn
        {block, 0} -> "## " <> block
        {<<"Bullet ", rest::binary>>, _} -> "- " <> rest
        {block, _} -> block
      end)

    "# Page 1\n\n" <> body <> "\n"
  end

  defp docx_fidelity_markdown_from_structured_content(content) do
    content
    |> strip_xml_tags()
    |> String.replace("\r\n", "\n")
    |> String.split(~r/\n{2,}/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index()
    |> Enum.map_join("\n\n", fn
      {block, 0} -> "## " <> block
      {<<"Bullet ", rest::binary>>, _} -> "- " <> rest
      {block, _} -> block
    end)
    |> Kernel.<>("\n")
  end

  defp strip_xml_tags(content) do
    content
    |> String.replace(~r/<[^>]+>/, "\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  defp soffice_convert_to_target(source_path, output_dir, target_format) do
    case soffice_command() do
      nil ->
        {:error, :soffice_not_found}

      soffice ->
        {output, exit_code} =
          run_soffice_command(soffice, [
            "--headless",
            "--convert-to",
            target_format,
            "--outdir",
            output_dir,
            source_path
          ])

        output_path =
          Path.join(output_dir, "#{Path.rootname(Path.basename(source_path))}.#{target_format}")

        with 0 <- exit_code,
             true <- File.exists?(output_path) do
          {:ok, output_path}
        else
          _ -> {:error, {:conversion_failed, output}}
        end
    end
  end

  defp extract_document_content(source_path, opts) do
    case runtime_test_overrides() do
      %{extract_from_file_result: result} ->
        result

      %{"extract_from_file_result" => result} ->
        result

      _ ->
        ExtractousEx.extract_from_file(source_path, opts)
    end
  end

  defp run_soffice_command(command, args) do
    case runtime_test_overrides() do
      %{soffice_cmd_result: result} ->
        result

      %{"soffice_cmd_result" => result} ->
        result

      _ ->
        System.cmd(command, args, stderr_to_stdout: true)
    end
  end

  defp runtime_test_overrides do
    Application.get_env(:rapid_tools, :document_converter_runtime_overrides, %{})
  end

  defp office_media_type("pdf"), do: "application/pdf"

  defp office_media_type("docx"),
    do: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
end
