defmodule RapidTools.VideoJoiner do
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

  def join(source_paths, target_format, opts \\ []) when is_list(source_paths) do
    target_format = normalize_format(target_format)

    with :ok <- validate_source_paths(source_paths),
         :ok <- validate_target_format(target_format),
         :ok <- ensure_sources_exist(source_paths),
         {:ok, output_dir} <- ensure_output_dir(opts),
         {:ok, command, args, output_path} <-
           command_for(source_paths, output_dir, target_format),
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
    Path.join(System.tmp_dir!(), "rapid_tools_together_videos")
  end

  defp command_for(source_paths, output_dir, target_format) do
    case System.find_executable("ffmpeg") do
      nil ->
        {:error, :ffmpeg_not_found}

      command ->
        output_path = Path.join(output_dir, "together-videos.#{target_format}")
        audio_flags = Enum.map(source_paths, &has_audio?/1)
        all_have_audio = Enum.all?(audio_flags)

        filter_complex = build_filter_complex(source_paths, audio_flags)

        inputs = Enum.flat_map(source_paths, fn path -> ["-i", path] end)

        maps = ["-map", "[outv]"] ++ if all_have_audio, do: ["-map", "[outa]"], else: []

        video_args = codec_video_args(target_format)
        audio_args = if all_have_audio, do: codec_audio_args(target_format), else: ["-an"]

        args =
          ["-y"] ++
            inputs ++
            ["-filter_complex", filter_complex] ++
            maps ++
            video_args ++ audio_args ++ [output_path]

        {:ok, command, args, output_path}
    end
  end

  defp has_audio?(path) do
    case System.find_executable("ffprobe") do
      nil ->
        true

      ffprobe ->
        args = [
          "-v",
          "error",
          "-select_streams",
          "a",
          "-show_entries",
          "stream=codec_type",
          "-of",
          "default=nw=1:nk=1",
          path
        ]

        case System.cmd(ffprobe, args, stderr_to_stdout: true) do
          {"", 0} -> false
          {_, 0} -> true
          _ -> true
        end
    end
  end

  defp build_filter_complex(source_paths, audio_flags) do
    n = length(source_paths)
    all_have_audio = Enum.all?(audio_flags)

    # Normalize every video to 1280x720, 30fps so concat never fails.
    normalized =
      source_paths
      |> Enum.with_index()
      |> Enum.map_join(";", fn {_path, i} ->
        "[#{i}:v]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:" <>
          "(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30[v#{i}]"
      end)

    # Build concat inputs.
    concat_inputs =
      source_paths
      |> Enum.with_index()
      |> Enum.map_join("", fn {_path, i} ->
        if all_have_audio do
          "[v#{i}][#{i}:a]"
        else
          "[v#{i}]"
        end
      end)

    concat = "#{concat_inputs}concat=n=#{n}:v=1:a=#{if(all_have_audio, do: 1, else: 0)}[outv]"
    concat = if all_have_audio, do: concat <> "[outa]", else: concat

    "#{normalized};#{concat}"
  end

  defp codec_video_args("mp4"), do: ["-c:v", "libx264", "-pix_fmt", "yuv420p"]
  defp codec_video_args("mov"), do: ["-c:v", "libx264", "-pix_fmt", "yuv420p"]
  defp codec_video_args("avi"), do: ["-c:v", "libx264", "-pix_fmt", "yuv420p"]
  defp codec_video_args("mkv"), do: ["-c:v", "libx264"]
  defp codec_video_args("webm"), do: ["-c:v", "libvpx-vp9"]

  defp codec_audio_args("mp4"), do: ["-c:a", "aac"]
  defp codec_audio_args("mov"), do: ["-c:a", "aac"]
  defp codec_audio_args("avi"), do: ["-c:a", "aac"]
  defp codec_audio_args("mkv"), do: ["-c:a", "aac"]
  defp codec_audio_args("webm"), do: ["-c:a", "libopus"]
end
