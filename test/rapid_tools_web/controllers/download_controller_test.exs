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
end
