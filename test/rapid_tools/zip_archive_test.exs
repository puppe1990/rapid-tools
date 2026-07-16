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

  test "build/2 returns an explicit error for empty entries" do
    assert {:error, :empty_entries} = ZipArchive.build("empty", [])
  end

  test "build/2 returns an error when a source file is missing instead of raising" do
    dir = ImageFixtures.temp_dir!("zip-archive-missing")
    missing = Path.join(dir, "missing.png")

    assert {:error, {:stage_failed, :enoent}} =
             ZipArchive.build("missing-test", [
               %{path: missing, filename: "image.png", media_type: "image/png"}
             ])
  end

  test "build/2 sanitizes nested filenames before staging" do
    dir = ImageFixtures.temp_dir!("zip-archive-nested-name")
    source = Path.join(dir, "source.png")
    File.write!(source, "payload")

    assert {:ok, zip_entry} =
             ZipArchive.build("nested-name", [
               %{
                 path: source,
                 filename: "../../evil/image.png",
                 media_type: "image/png"
               }
             ])

    assert File.exists?(zip_entry.path)

    {listing, 0} = System.cmd("unzip", ["-Z1", zip_entry.path], stderr_to_stdout: true)
    assert listing =~ "image.png"
    refute listing =~ "evil"
  end
end
