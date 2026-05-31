defmodule RapidTools.ImagesToVideoConverter do
  @moduledoc """
  Converts a list of images into a video (MP4) or animated GIF.
  """

  @supported_formats ~w(mp4 gif)

  @media_types %{
    "mp4" => "video/mp4",
    "gif" => "image/gif"
  }

  def supported_formats, do: @supported_formats

  def convert(source_paths, target_format, opts \\ []) when is_list(source_paths) do
    target_format = normalize_format(target_format)
    interval = Keyword.get(opts, :interval, 2)

    with :ok <- validate_source_paths(source_paths),
         :ok <- validate_target_format(target_format),
         :ok <- ensure_sources_exist(source_paths),
         {:ok, output_dir} <- ensure_output_dir(opts),
         {:ok, output_path} <- build_output_path(output_dir, target_format),
         {:ok, segment_paths} <- build_segments(source_paths, interval, output_dir),
         {:ok, concat_file} <- build_concat_file(segment_paths, output_dir),
         {:ok, command, args} <- command_for(concat_file, output_path, target_format),
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

  defp validate_source_paths(source_paths) when source_paths != [], do: :ok
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
    Path.join(System.tmp_dir!(), "rapid_tools_images_to_video")
  end

  defp build_output_path(output_dir, target_format) do
    {:ok, Path.join(output_dir, "images-to-video.#{target_format}")}
  end

  defp build_segments(source_paths, interval, output_dir) do
    ffmpeg = System.find_executable("ffmpeg")

    if ffmpeg == nil do
      {:error, :ffmpeg_not_found}
    else
      segment_paths =
        Enum.with_index(source_paths, fn path, index ->
          segment_path = Path.join(output_dir, "segment_#{index}.mp4")

          args = [
            "-y",
            "-loop",
            "1",
            "-i",
            path,
            "-vf",
            "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:black",
            "-c:v",
            "libx264",
            "-t",
            "#{interval}",
            "-pix_fmt",
            "yuv420p",
            "-an",
            segment_path
          ]

          {_, 0} = System.cmd(ffmpeg, args, stderr_to_stdout: true)
          segment_path
        end)

      {:ok, segment_paths}
    end
  end

  defp build_concat_file(segment_paths, output_dir) do
    concat_path = Path.join(output_dir, "concat_list.txt")

    lines =
      segment_paths
      |> Enum.map(fn path -> "file '#{path}'" end)

    content = Enum.join(lines, "\n") <> "\n"

    case File.write(concat_path, content) do
      :ok -> {:ok, concat_path}
      {:error, reason} -> {:error, {:concat_file_error, reason}}
    end
  end

  defp command_for(concat_file, output_path, "mp4") do
    case System.find_executable("ffmpeg") do
      nil ->
        {:error, :ffmpeg_not_found}

      command ->
        args = [
          "-y",
          "-f",
          "concat",
          "-safe",
          "0",
          "-i",
          concat_file,
          "-c",
          "copy",
          output_path
        ]

        {:ok, command, args}
    end
  end

  defp command_for(concat_file, output_path, "gif") do
    case System.find_executable("ffmpeg") do
      nil ->
        {:error, :ffmpeg_not_found}

      command ->
        args = [
          "-y",
          "-f",
          "concat",
          "-safe",
          "0",
          "-i",
          concat_file,
          "-vf",
          "fps=10,scale=480:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer",
          "-loop",
          "0",
          output_path
        ]

        {:ok, command, args}
    end
  end
end
