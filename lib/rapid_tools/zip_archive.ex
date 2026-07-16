defmodule RapidTools.ZipArchive do
  @moduledoc false

  def build(id, entries) when is_list(entries) and entries != [] do
    case prepare_workspace(id) do
      {:ok, zip_command, zip_path, staging_dir} ->
        archive_staged_entries(zip_command, zip_path, staging_dir, entries)

      {:error, _} = error ->
        error
    end
  end

  def build(_id, []), do: {:error, :empty_entries}

  defp prepare_workspace(id) do
    zip_dir = Path.join(System.tmp_dir!(), "rapid_tools_zip_downloads")
    zip_path = Path.join(zip_dir, "rapid-tools-#{id}.zip")
    staging_dir = Path.join(zip_dir, "staging-#{id}")

    with {:ok, zip_command} <- find_zip(),
         :ok <- mkdir_p(zip_dir) do
      File.rm_rf(staging_dir)

      case mkdir_p(staging_dir) do
        :ok -> {:ok, zip_command, zip_path, staging_dir}
        {:error, _} = error -> error
      end
    end
  end

  defp archive_staged_entries(zip_command, zip_path, staging_dir, entries) do
    case stage_entries(entries, staging_dir) do
      {:ok, staged_paths} ->
        File.rm(zip_path)
        run_zip(zip_command, ["-j", "-q", zip_path] ++ staged_paths, zip_path)

      {:error, _} = error ->
        error
    end
  end

  defp find_zip do
    case System.find_executable("zip") do
      nil -> {:error, :zip_not_found}
      command -> {:ok, command}
    end
  end

  defp mkdir_p(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  defp stage_entries(entries, staging_dir) do
    result =
      Enum.reduce_while(entries, {[], %{}}, fn entry, {acc, used} ->
        filename = unique_filename(safe_filename(entry.filename), used)
        staged_path = Path.join(staging_dir, filename)

        case File.cp(entry.path, staged_path) do
          :ok ->
            {:cont, {[staged_path | acc], Map.update(used, filename, 1, &(&1 + 1))}}

          {:error, reason} ->
            {:halt, {:error, {:stage_failed, reason}}}
        end
      end)

    case result do
      {:error, _} = error -> error
      {staged_paths, _used} -> {:ok, Enum.reverse(staged_paths)}
    end
  end

  defp run_zip(zip_command, args, zip_path) do
    case System.cmd(zip_command, args, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok,
         %{
           path: zip_path,
           filename: Path.basename(zip_path),
           media_type: "application/zip"
         }}

      {output, exit_code} ->
        {:error, {:zip_failed, exit_code, output}}
    end
  rescue
    error ->
      {:error, {:zip_exception, Exception.message(error)}}
  end

  defp safe_filename(filename) when is_binary(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/[\x00-\x1F\x7F]/, "_")
    |> case do
      "" -> "file"
      name -> name
    end
  end

  defp safe_filename(_), do: "file"

  defp unique_filename(filename, used) do
    case Map.get(used, filename) do
      nil ->
        filename

      count ->
        ext = Path.extname(filename)
        base = Path.rootname(filename, ext)
        "#{base} (#{count + 1})#{ext}"
    end
  end
end
