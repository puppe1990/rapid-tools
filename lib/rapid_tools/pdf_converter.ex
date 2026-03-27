defmodule RapidTools.PdfConverter do
  @moduledoc false

  @supported_modes ~w(pdf_to_png pdf_to_jpg images_to_pdf)
  @supported_image_formats ~w(png jpg)

  def supported_modes, do: @supported_modes
  def supported_image_formats, do: @supported_image_formats

  def pdf_to_images(source_path, target_format, opts \\ []) do
    target_format = normalize_value(target_format)

    with :ok <- validate_image_format(target_format),
         :ok <- ensure_source_exists(source_path),
         {:ok, output_dir} <- ensure_output_dir(opts),
         {:ok, command, args, output_pattern} <-
           pdf_to_images_command(source_path, output_dir, target_format),
         {_, 0} <- System.cmd(command, args, stderr_to_stdout: true) do
      results =
        output_pattern
        |> Path.wildcard()
        |> Enum.sort()
        |> Enum.map(fn output_path ->
          %{
            output_path: output_path,
            filename: Path.basename(output_path),
            media_type: image_media_type(target_format),
            target_format: target_format
          }
        end)

      {:ok, results}
    else
      {:error, _} = error ->
        error

      {_output, exit_code} ->
        {:error, {:conversion_failed, exit_code}}
    end
  end

  def images_to_pdf(source_paths, opts \\ []) when is_list(source_paths) do
    with :ok <- validate_source_paths(source_paths),
         {:ok, output_dir} <- ensure_output_dir(opts),
         {:ok, command, args, output_path} <- images_to_pdf_command(source_paths, output_dir),
         {_, 0} <- System.cmd(command, args, stderr_to_stdout: true) do
      {:ok,
       %{
         output_path: output_path,
         filename: Path.basename(output_path),
         media_type: "application/pdf",
         target_format: "pdf"
       }}
    else
      {:error, _} = error ->
        error

      {_output, exit_code} ->
        {:error, {:conversion_failed, exit_code}}
    end
  end

  defp normalize_value(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp validate_image_format(format) when format in @supported_image_formats, do: :ok
  defp validate_image_format(format), do: {:error, {:unsupported_target_format, format}}

  defp validate_source_paths([]), do: {:error, :source_files_not_found}

  defp validate_source_paths(source_paths) do
    if Enum.all?(source_paths, &File.exists?/1),
      do: :ok,
      else: {:error, :source_files_not_found}
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

  defp default_output_dir do
    Path.join(System.tmp_dir!(), "rapid_tools_pdf_conversions")
  end

  defp pdf_to_images_command(source_path, output_dir, target_format) do
    case System.find_executable("magick") || System.find_executable("convert") do
      nil ->
        {:error, :imagemagick_not_found}

      command ->
        output_pattern =
          Path.join(
            output_dir,
            "#{Path.rootname(Path.basename(source_path))}-*.#{target_format}"
          )

        output_template =
          Path.join(
            output_dir,
            "#{Path.rootname(Path.basename(source_path))}-%02d.#{target_format}"
          )

        args = ["-density", "144", source_path, "-quality", "92", output_template]
        {:ok, command, args, output_pattern}
    end
  end

  defp images_to_pdf_command(source_paths, output_dir) do
    case System.find_executable("magick") || System.find_executable("convert") do
      nil ->
        {:error, :imagemagick_not_found}

      command ->
        output_path = Path.join(output_dir, "combined-images.pdf")
        {:ok, command, source_paths ++ [output_path], output_path}
    end
  end

  defp image_media_type("png"), do: "image/png"
  defp image_media_type("jpg"), do: "image/jpeg"
end
