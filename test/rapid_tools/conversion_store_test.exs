defmodule RapidTools.ConversionStoreTest do
  use ExUnit.Case, async: false

  alias RapidTools.ConversionStore

  test "put/1 persists an entry that can be fetched by id" do
    entry = %{path: "/tmp/example.jpg", filename: "example.jpg", media_type: "image/jpeg"}

    assert {:ok, id} = ConversionStore.put(entry)
    assert {:ok, stored} = ConversionStore.fetch(id)
    assert stored.path == entry.path
    assert stored.filename == entry.filename
    assert stored.media_type == entry.media_type
  end

  test "put_batch/1 persists batch entries that can be fetched by id" do
    entries = [
      %{path: "/tmp/example-1.jpg", filename: "example-1.jpg", media_type: "image/jpeg"},
      %{path: "/tmp/example-2.jpg", filename: "example-2.jpg", media_type: "image/jpeg"}
    ]

    assert {:ok, id} = ConversionStore.put_batch(entries)
    assert {:ok, stored} = ConversionStore.fetch_batch(id)
    assert Enum.map(stored, & &1.filename) == ["example-1.jpg", "example-2.jpg"]
  end
end
