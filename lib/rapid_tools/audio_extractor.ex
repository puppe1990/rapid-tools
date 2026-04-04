defmodule RapidTools.AudioExtractor do
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

  def extract(source_path, target_format, opts \\ []) do
    target_format = normalize_format(target_format)

    with :ok <- validate_target_format(target_format),
         :ok <- ensure_source_exists(source_path),
         :ok <- ensure_source_has_audio_stream(source_path),
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

  defp ensure_source_has_audio_stream(source_path) do
    case System.find_executable("ffprobe") do
      nil ->
        :ok

      command ->
        source_path
        |> ffprobe_audio_stream_args()
        |> then(&System.cmd(command, &1, stderr_to_stdout: true))
        |> validate_ffprobe_output()
    end
  end

  defp ffprobe_audio_stream_args(source_path) do
    [
      "-v",
      "error",
      "-select_streams",
      "a:0",
      "-show_entries",
      "stream=codec_type",
      "-of",
      "default=noprint_wrappers=1:nokey=1",
      source_path
    ]
  end

  defp validate_ffprobe_output({output, 0}) do
    if String.contains?(output, "audio"), do: :ok, else: {:error, :no_audio_stream}
  end

  defp validate_ffprobe_output({_output, _exit_code}), do: {:error, :invalid_media_file}

  defp ensure_output_dir(opts) do
    output_dir = Keyword.get(opts, :output_dir, default_output_dir())

    case File.mkdir_p(output_dir) do
      :ok -> {:ok, output_dir}
      {:error, reason} -> {:error, {:output_dir_error, reason}}
    end
  end

  defp default_output_dir do
    Path.join(System.tmp_dir!(), "rapid_tools_audio_extractions")
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

        args =
          [
            "-y",
            "-i",
            source_path,
            "-vn"
          ] ++ codec_args(target_format) ++ [output_path]

        {:ok, command, args, output_path}
    end
  end

  defp codec_args("mp3"), do: ["-c:a", "libmp3lame"]
  defp codec_args("wav"), do: ["-c:a", "pcm_s16le"]
  defp codec_args("ogg"), do: ["-c:a", "libvorbis"]
  defp codec_args("aac"), do: ["-c:a", "aac"]
  defp codec_args("flac"), do: ["-c:a", "flac"]
end
