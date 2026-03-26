defmodule RapidToolsWeb.DownloadController do
  use RapidToolsWeb, :controller

  alias RapidTools.ConversionStore
  alias RapidTools.ZipArchive

  def show(conn, %{"id" => id}) do
    with {:ok, entry} <- ConversionStore.fetch(id),
         true <- File.exists?(entry.path) do
      send_download(conn, {:file, entry.path},
        filename: entry.filename,
        content_type: entry.media_type
      )
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> put_view(RapidToolsWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  def batch(conn, %{"id" => id}) do
    with {:ok, entries} <- ConversionStore.fetch_batch(id),
         true <- entries != [],
         {:ok, zip_entry} <- ZipArchive.build(id, entries) do
      send_download(conn, {:file, zip_entry.path},
        filename: zip_entry.filename,
        content_type: zip_entry.media_type
      )
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> put_view(RapidToolsWeb.ErrorHTML)
        |> render(:"404")
    end
  end
end
