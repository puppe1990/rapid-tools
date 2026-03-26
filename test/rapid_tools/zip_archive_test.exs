defmodule RapidTools.ZipArchiveTest do
  use ExUnit.Case, async: false

  alias RapidTools.TestSupport.ImageFixtures
  alias RapidTools.ZipArchive

  test "build/2 creates a zip even when filenames repeat" do
    dir = ImageFixtures.temp_dir!("zip-archive-duplicates")
    first = Path.join(dir, "first.png")
    second = Path.join(dir, "second.png")

    File.write!(first, "one")
    File.write!(second, "two")

    assert {:ok, zip_entry} =
             ZipArchive.build("dup-test", [
               %{path: first, filename: "image.png", media_type: "image/png"},
               %{path: second, filename: "image.png", media_type: "image/png"}
             ])

    assert File.exists?(zip_entry.path)

    {listing, 0} = System.cmd("unzip", ["-Z1", zip_entry.path], stderr_to_stdout: true)
    assert listing =~ "image.png"
    assert listing =~ "image (2).png"
  end
end
