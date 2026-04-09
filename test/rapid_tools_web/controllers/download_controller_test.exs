defmodule RapidToolsWeb.DownloadControllerTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.ConversionStore
  alias RapidTools.TestSupport.ImageFixtures

  test "GET /downloads/batches/:id.zip returns a zip with converted files", %{conn: conn} do
    dir = ImageFixtures.temp_dir!("zip-download")
    first = Path.join(dir, "first.webp")
    second = Path.join(dir, "second.webp")

    File.write!(first, "first-file")
    File.write!(second, "second-file")

    assert {:ok, batch_id} =
             ConversionStore.put_batch([
               %{path: first, filename: "first.webp", media_type: "image/webp"},
               %{path: second, filename: "second.webp", media_type: "image/webp"}
             ])

    conn = get(conn, "/downloads/batches/#{batch_id}")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["application/zip"]

    [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ".zip"
    assert byte_size(conn.resp_body) > 0
  end

  test "GET /downloads/:id returns a single converted file", %{conn: conn} do
    dir = ImageFixtures.temp_dir!("single-download")
    file_path = Path.join(dir, "image.png")

    File.write!(file_path, "image-content")

    {:ok, id} =
      ConversionStore.put(%{
        path: file_path,
        filename: "image.png",
        media_type: "image/png"
      })

    conn = get(conn, "/downloads/#{id}")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/png"]

    [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "image.png"
    assert conn.resp_body == "image-content"
  end

  test "GET /downloads/:id returns 404 for non-existent id", %{conn: conn} do
    conn = get(conn, "/downloads/non-existent-id")
    assert conn.status == 404
  end

  test "GET /downloads/batches/:id returns 404 for non-existent batch", %{conn: conn} do
    conn = get(conn, "/downloads/batches/non-existent-batch")
    assert conn.status == 404
  end
end
