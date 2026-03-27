defmodule RapidTools.VideoConverter do
  @moduledoc false

  @supported_formats ~w(mp4 mov webm mkv avi)
  @media_types %{
    "avi" => "video/x-msvideo",
    "mkv" => "video/x-matroska",
    "mov" => "video/quicktime",
    "mp4" => "video/mp4",
    "webm" => "video/webm"
  }

  def supported_formats, do: @supported_formats

  def convert(source_path, target_format, opts \\ []) do
    target_format = normalize_format(target_format)

    with :ok <- validate_target_format(target_format),
         :ok <- ensure_source_exists(source_path),
         {:ok, output_dir} <- ensure_output_dir(opts),
         {:ok, command, args, output_path} <- command_for(source_path, output_dir, target_format),
         {_, 0} <- System.cmd(command, args, stderr_to_stdout: true) do
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
    Path.join(System.tmp_dir!(), "rapid_tools_video_conversions")
  end

  defp command_for(source_path, output_dir, target_format) do
    case System.find_executable("ffmpeg") do
      nil ->
        {:error, :ffmpeg_not_found}

      command ->
        output_path =
          Path.join(
            output_dir,
            "#{Path.rootname(Path.basename(source_path))}.#{target_format}"
          )

        args = [
          "-y",
          "-i",
          source_path,
          "-movflags",
          "+faststart",
          output_path
        ]

        {:ok, command, args, output_path}
    end
  end
end
