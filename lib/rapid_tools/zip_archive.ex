defmodule RapidTools.ZipArchive do
  @moduledoc false

  def build(id, entries) when is_list(entries) and entries != [] do
    zip_dir = Path.join(System.tmp_dir!(), "rapid_tools_zip_downloads")
    File.mkdir_p!(zip_dir)
    zip_path = Path.join(zip_dir, "rapid-tools-#{id}.zip")
    staging_dir = Path.join(zip_dir, "staging-#{id}")
    File.rm_rf(staging_dir)
    File.mkdir_p!(staging_dir)

    staged_paths =
      entries
      |> stage_entries(staging_dir)
      |> Enum.map(& &1.path)

    File.rm(zip_path)
    args = ["-j", "-q", zip_path] ++ staged_paths

    case System.cmd("zip", args, stderr_to_stdout: true) do
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
  end

  defp stage_entries(entries, staging_dir) do
    {staged_entries, _used} =
      Enum.map_reduce(entries, %{}, fn entry, used ->
        filename = unique_filename(entry.filename, used)
        staged_path = Path.join(staging_dir, filename)
        File.cp!(entry.path, staged_path)
        {Map.put(entry, :path, staged_path), Map.update(used, filename, 1, &(&1 + 1))}
      end)

    staged_entries
  end

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
