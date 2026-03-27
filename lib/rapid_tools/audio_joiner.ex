defmodule RapidTools.AudioJoiner do
  @moduledoc false

  @supported_formats ~w(mp3 wav ogg aac flac)
  @media_types %{
    "aac" => "audio/aac",
    "flac" => "audio/flac",
    "mp3" => "audio/mpeg",
    "ogg" => "audio/ogg",
    "wav" => "audio/wav"
  }

  def supported_formats, do: @supported_formats

  def join(source_paths, target_format, opts \\ []) when is_list(source_paths) do
    target_format = normalize_format(target_format)

    with :ok <- validate_source_paths(source_paths),
         :ok <- validate_target_format(target_format),
         :ok <- ensure_sources_exist(source_paths),
         {:ok, output_dir} <- ensure_output_dir(opts),
         {:ok, command, args, output_path} <- command_for(source_paths, output_dir, target_format),
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
        {:error, {:join_failed, exit_code}}
    end
  end

  defp normalize_format(format) do
    format
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp validate_source_paths(source_paths) when length(source_paths) >= 2, do: :ok
  defp validate_source_paths(_source_paths), do: {:error, :not_enough_source_files}

  defp validate_target_format(target_format) when target_format in @supported_formats, do: :ok

  defp validate_target_format(target_format),
    do: {:error, {:unsupported_target_format, target_format}}

  defp ensure_sources_exist(source_paths) do
    if Enum.all?(source_paths, &File.exists?/1),
      do: :ok,
      else: {:error, :source_file_not_found}
  end

  defp ensure_output_dir(opts) do
    output_dir = Keyword.get(opts, :output_dir, default_output_dir())

    case File.mkdir_p(output_dir) do
      :ok -> {:ok, output_dir}
      {:error, reason} -> {:error, {:output_dir_error, reason}}
    end
  end

  defp default_output_dir do
    Path.join(System.tmp_dir!(), "rapid_tools_together_audios")
  end

  defp command_for(source_paths, output_dir, target_format) do
    case System.find_executable("ffmpeg") do
      nil ->
        {:error, :ffmpeg_not_found}

      command ->
        output_path = Path.join(output_dir, "together-audios.#{target_format}")

        filter_complex =
          source_paths
          |> Enum.with_index()
          |> Enum.map_join("", fn {_path, index} -> "[#{index}:a]" end)
          |> Kernel.<>("concat=n=#{length(source_paths)}:v=0:a=1[outa]")

        args =
          ["-y"] ++
            Enum.flat_map(source_paths, fn source_path -> ["-i", source_path] end) ++
            ["-filter_complex", filter_complex, "-map", "[outa]", "-vn"] ++
            codec_args(target_format) ++ [output_path]

        {:ok, command, args, output_path}
    end
  end

  defp codec_args("mp3"), do: ["-c:a", "libmp3lame"]
  defp codec_args("wav"), do: ["-c:a", "pcm_s16le"]
  defp codec_args("ogg"), do: ["-c:a", "libvorbis"]
  defp codec_args("aac"), do: ["-c:a", "aac"]
  defp codec_args("flac"), do: ["-c:a", "flac"]
end
