defmodule RapidTools.ImageResizer do
  @moduledoc false

  @supported_formats ~w(original jpg png webp)
  @supported_fits ~w(contain cover stretch)
  @media_types %{
    "jpg" => "image/jpeg",
    "png" => "image/png",
    "webp" => "image/webp"
  }

  def supported_formats, do: @supported_formats
  def supported_fits, do: @supported_fits

  def resize(source_path, width, height, opts \\ []) do
    target_format =
      opts
      |> Keyword.get(:target_format, "original")
      |> normalize_format()

    fit =
      opts
      |> Keyword.get(:fit, "contain")
      |> normalize_fit()

    with :ok <- validate_target_format(target_format),
         :ok <- validate_fit(fit),
         {:ok, width} <- normalize_dimension(width),
         {:ok, height} <- normalize_dimension(height),
         :ok <- ensure_source_exists(source_path),
         {:ok, output_dir} <- ensure_output_dir(opts),
         {:ok, command, args, output_path, actual_format} <-
           command_for(source_path, output_dir, width, height, fit, target_format),
         {_, 0} <- System.cmd(command, args, stderr_to_stdout: true) do
      {:ok,
       %{
         output_path: output_path,
         filename: Path.basename(output_path),
         media_type: Map.fetch!(@media_types, actual_format),
         target_format: actual_format,
         width: width,
         height: height,
         fit: fit
       }}
    else
      {:error, _} = error ->
        error

      {_output, exit_code} ->
        {:error, {:resize_failed, exit_code}}
    end
  end

  defp normalize_format(format) do
    format
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_fit(fit) do
    fit
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_dimension(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp normalize_dimension(value) do
    case Integer.parse(to_string(value)) do
      {dimension, ""} when dimension > 0 -> {:ok, dimension}
      _ -> {:error, :invalid_dimension}
    end
  end

  defp validate_target_format(target_format) when target_format in @supported_formats, do: :ok

  defp validate_target_format(target_format),
    do: {:error, {:unsupported_target_format, target_format}}

  defp validate_fit(fit) when fit in @supported_fits, do: :ok
  defp validate_fit(fit), do: {:error, {:unsupported_fit, fit}}

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
    Path.join(System.tmp_dir!(), "rapid_tools_image_resizes")
  end

  defp command_for(source_path, output_dir, width, height, fit, target_format) do
    case System.find_executable("magick") || System.find_executable("convert") do
      nil ->
        {:error, :imagemagick_not_found}

      command ->
        actual_format = output_format(source_path, target_format)

        output_path =
          Path.join(
            output_dir,
            "#{Path.rootname(Path.basename(source_path))}-#{width}x#{height}.#{actual_format}"
          )

        args =
          [source_path]
          |> Kernel.++(resize_args(width, height, fit))
          |> Kernel.++([output_path])

        {:ok, command, args, output_path, actual_format}
    end
  end

  defp output_format(source_path, "original") do
    source_path
    |> Path.extname()
    |> String.trim_leading(".")
    |> normalize_format()
    |> case do
      "jpeg" -> "jpg"
      format -> format
    end
  end

  defp output_format(_source_path, target_format), do: target_format

  defp resize_args(width, height, "contain"), do: ["-resize", "#{width}x#{height}"]

  defp resize_args(width, height, "cover"),
    do: ["-resize", "#{width}x#{height}^", "-gravity", "center", "-extent", "#{width}x#{height}"]

  defp resize_args(width, height, "stretch"), do: ["-resize", "#{width}x#{height}!"]
end
