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

  @orientations ~w(original landscape portrait square)

  def supported_orientations, do: @orientations

  def convert(source_path, target_format, opts \\ []) do
    target_format = normalize_format(target_format)
    orientation = normalize_orientation(Keyword.get(opts, :orientation, "original"))

    with :ok <- validate_target_format(target_format),
         :ok <- validate_orientation(orientation),
         :ok <- ensure_source_exists(source_path),
         :ok <- ensure_source_has_video_stream(source_path),
         {:ok, output_dir} <- ensure_output_dir(opts),
         {:ok, command, args, output_path} <-
           command_for(source_path, output_dir, target_format, orientation),
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

  defp normalize_orientation(orientation) do
    orientation
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp validate_target_format(target_format) when target_format in @supported_formats, do: :ok

  defp validate_target_format(target_format),
    do: {:error, {:unsupported_target_format, target_format}}

  defp validate_orientation(orientation) when orientation in @orientations, do: :ok

  defp validate_orientation(orientation),
    do: {:error, {:unsupported_orientation, orientation}}

  defp ensure_source_exists(source_path) do
    if File.exists?(source_path), do: :ok, else: {:error, :source_file_not_found}
  end

  defp ensure_source_has_video_stream(source_path) do
    case System.find_executable("ffprobe") do
      nil ->
        :ok

      command ->
        source_path
        |> ffprobe_video_stream_args()
        |> then(&System.cmd(command, &1, stderr_to_stdout: true))
        |> validate_ffprobe_output()
    end
  end

  defp ffprobe_video_stream_args(source_path) do
    [
      "-v",
      "error",
      "-select_streams",
      "v:0",
      "-show_entries",
      "stream=codec_type",
      "-of",
      "default=noprint_wrappers=1:nokey=1",
      source_path
    ]
  end

  defp validate_ffprobe_output({output, 0}) do
    if String.contains?(output, "video"), do: :ok, else: {:error, :no_video_stream}
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
    Path.join(System.tmp_dir!(), "rapid_tools_video_conversions")
  end

  defp command_for(source_path, output_dir, target_format, orientation) do
    case System.find_executable("ffmpeg") do
      nil ->
        {:error, :ffmpeg_not_found}

      command ->
        output_path =
          Path.join(
            output_dir,
            "#{Path.rootname(Path.basename(source_path))}.#{target_format}"
          )

        filter = orientation_filter(orientation, source_path)

        args =
          [
            "-y",
            "-i",
            source_path
          ] ++
            filter_args(filter) ++
            [
              "-movflags",
              "+faststart",
              output_path
            ]

        {:ok, command, args, output_path}
    end
  end

  defp filter_args(nil), do: []
  defp filter_args(filter), do: ["-vf", filter]

  defp orientation_filter("original", _source_path), do: nil

  defp orientation_filter("square", _source_path) do
    "crop=min(iw\\,ih):min(iw\\,ih):(iw-min(iw\\,ih))/2:(ih-min(iw\\,ih))/2"
  end

  defp orientation_filter(orientation, source_path)
       when orientation in ["landscape", "portrait"] do
    case get_video_dimensions(source_path) do
      nil ->
        nil

      {width, height} when orientation == "landscape" and height > width ->
        "transpose=1"

      {width, height} when orientation == "portrait" and width > height ->
        "transpose=2"

      _ ->
        nil
    end
  end

  defp orientation_filter(_orientation, _source_path), do: nil

  defp get_video_dimensions(source_path) do
    case System.find_executable("ffprobe") do
      nil ->
        nil

      command ->
        args = [
          "-v",
          "error",
          "-select_streams",
          "v:0",
          "-show_entries",
          "stream=width,height",
          "-of",
          "csv=p=0",
          source_path
        ]

        case System.cmd(command, args, stderr_to_stdout: true) do
          {output, 0} -> parse_dimensions(output)
          _ -> nil
        end
    end
  end

  defp parse_dimensions(output) do
    case String.trim(output) |> String.split(",") do
      [w, h] -> {String.to_integer(w), String.to_integer(h)}
      _ -> nil
    end
  end
end
