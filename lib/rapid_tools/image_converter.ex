defmodule RapidTools.ImageConverter do
  @moduledoc false

  @supported_formats ~w(jpg png webp heic avif)
  @media_types %{
    "jpg" => "image/jpeg",
    "png" => "image/png",
    "webp" => "image/webp",
    "heic" => "image/heic",
    "avif" => "image/avif"
  }

  def supported_formats, do: @supported_formats

  def convert(source_path, target_format, opts \\ []) do
    target_format = normalize_format(target_format)

    with :ok <- validate_target_format(target_format),
         :ok <- ensure_source_exists(source_path),
         {:ok, output_dir} <- ensure_output_dir(opts),
         {:ok, command, args} <- command_for(source_path, output_dir, target_format),
         {_, 0} <- System.cmd(command, args, stderr_to_stdout: true) do
      output_path = List.last(args)

      {:ok,
       %{
         output_path: output_path,
         filename: Path.basename(output_path),
         media_type: Map.fetch!(@media_types, target_format),
         target_format: target_format
       }}
    else
      {:error, _} = error ->
        error

      {_output, exit_code} ->
        {:error, {:conversion_failed, exit_code}}
    end
  end

  defp normalize_format(format) do
    format
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp validate_target_format(target_format) when target_format in @supported_formats, do: :ok

  defp validate_target_format(target_format),
    do: {:error, {:unsupported_target_format, target_format}}

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
    Path.join(System.tmp_dir!(), "rapid_tools_conversions")
  end

  defp command_for(source_path, output_dir, target_format) do
    output_path =
      Path.join(
        output_dir,
        "#{Path.rootname(Path.basename(source_path))}.#{target_format}"
      )

    case System.find_executable("magick") || System.find_executable("convert") do
      nil ->
        {:error, :imagemagick_not_found}

      command ->
        args =
          if Path.basename(command) == "magick" do
            [source_path, output_path]
          else
            [source_path, output_path]
          end

        {:ok, command, args}
    end
  end
end
