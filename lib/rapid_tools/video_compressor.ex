defmodule RapidTools.VideoCompressor do
  @moduledoc false

  @supported_presets ~w(small balanced high)
  @supported_resolutions ~w(original 1080 720 480)

  def supported_presets, do: @supported_presets
  def supported_resolutions, do: @supported_resolutions

  def compress(source_path, opts \\ []) do
    preset =
      opts
      |> Keyword.get(:preset, "balanced")
      |> normalize_value()

    max_resolution =
      opts
      |> Keyword.get(:max_resolution, "original")
      |> normalize_value()

    mute = Keyword.get(opts, :mute, false)

    with :ok <- validate_preset(preset),
         :ok <- validate_resolution(max_resolution),
         :ok <- ensure_source_exists(source_path),
         {:ok, output_dir} <- ensure_output_dir(opts),
         {:ok, command, args, output_path} <-
           command_for(source_path, output_dir, preset, max_resolution, mute),
         {_, 0} <- System.cmd(command, args, stderr_to_stdout: true) do
      {:ok,
       %{
         output_path: output_path,
         filename: Path.basename(output_path),
         media_type: "video/mp4",
         target_format: "mp4",
         preset: preset,
         max_resolution: max_resolution
       }}
    else
      {:error, _} = error ->
        error

      {_output, exit_code} ->
        {:error, {:compression_failed, exit_code}}
    end
  end

  defp normalize_value(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp validate_preset(preset) when preset in @supported_presets, do: :ok
  defp validate_preset(preset), do: {:error, {:unsupported_preset, preset}}

  defp validate_resolution(resolution) when resolution in @supported_resolutions, do: :ok
  defp validate_resolution(resolution), do: {:error, {:unsupported_resolution, resolution}}

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
    Path.join(System.tmp_dir!(), "rapid_tools_video_compressions")
  end

  defp command_for(source_path, output_dir, preset, max_resolution, mute) do
    case System.find_executable("ffmpeg") do
      nil ->
        {:error, :ffmpeg_not_found}

      command ->
        output_path =
          Path.join(output_dir, "#{Path.rootname(Path.basename(source_path))}-compressed.mp4")

        args =
          [
            "-y",
            "-i",
            source_path,
            "-c:v",
            "libx264"
          ] ++
            resolution_args(max_resolution) ++
            preset_args(preset) ++
            audio_args(mute) ++ ["-movflags", "+faststart", output_path]

        {:ok, command, args, output_path}
    end
  end

  defp preset_args("small"), do: ["-preset", "veryfast", "-crf", "34"]
  defp preset_args("balanced"), do: ["-preset", "medium", "-crf", "29"]
  defp preset_args("high"), do: ["-preset", "slow", "-crf", "24"]

  defp resolution_args("original"), do: []

  defp resolution_args("1080"),
    do: ["-vf", "scale=w='min(1920,iw)':h='min(1080,ih)':force_original_aspect_ratio=decrease"]

  defp resolution_args("720"),
    do: ["-vf", "scale=w='min(1280,iw)':h='min(720,ih)':force_original_aspect_ratio=decrease"]

  defp resolution_args("480"),
    do: ["-vf", "scale=w='min(854,iw)':h='min(480,ih)':force_original_aspect_ratio=decrease"]

  defp audio_args(true), do: ["-an"]
  defp audio_args(false), do: ["-c:a", "aac", "-b:a", "128k"]
end
