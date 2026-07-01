defmodule RapidTools.QrReader do
  @moduledoc false

  def available? do
    case Application.get_env(:rapid_tools, :qr_reader_available) do
      nil -> is_binary(System.find_executable("zbarimg"))
      value -> value
    end
  end

  def read(source_path) do
    with :ok <- ensure_source_exists(source_path),
         {:ok, command} <- zbar_command() do
      decode_with_zbar(command, source_path)
    end
  end

  defp ensure_source_exists(source_path) do
    if File.exists?(source_path), do: :ok, else: {:error, :source_file_not_found}
  end

  defp zbar_command do
    case System.find_executable("zbarimg") do
      nil -> {:error, :zbar_unavailable}
      command -> {:ok, command}
    end
  end

  defp decode_with_zbar(command, source_path) do
    args = ["-q", "--raw", source_path]

    case System.cmd(command, args, stderr_to_stdout: true) do
      {output, 0} ->
        case parse_output(output) do
          nil -> {:error, :no_qr_found}
          text -> {:ok, text}
        end

      {_output, _exit_code} ->
        {:error, :no_qr_found}
    end
  end

  defp parse_output(output) do
    output
    |> String.split("\n", trim: true)
    |> List.first()
    |> case do
      nil -> nil
      line -> String.trim(line)
    end
    |> case do
      "" -> nil
      text -> text
    end
  end
end
