defmodule RapidTools.TestSupport.ImageFixtures do
  @moduledoc false

  @oriented_jpeg_base64 """
  /9j/4AAQSkZJRgABAQEASABIAAD/4QBiRXhpZgAATU0AKgAAAAgABQESAAMAAAABAAYAAAEaAAUAAAABAAAASgEbAAUAAAABAAAAUgEoAAMAAAABAAIAAAITAAMAAAABAAEAAAAAAAAAAABIAAAAAQAAAEgAAAAB/9sAQwAJBgYIBgUJCAcICgkJCg0WDg0MDA0aExQQFh8cISAfHB4eIycyKiMlLyUeHis7LC8zNTg4OCEqPUE8NkEyNzg1/9sAQwEJCgoNCw0ZDg4ZNSQeJDU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1NTU1/8AAEQgAHgAUAwEiAAIRAQMRAf/EABkAAAMBAQEAAAAAAAAAAAAAAAAGBwUDBP/EACoQAAICAQMDAgUFAAAAAAAAAAECAwQRAAUhBhIxE2EHFEGBsRUiUZGi/8QAFgEBAQEAAAAAAAAAAAAAAAAAAwQA/8QAGREAAgMBAAAAAAAAAAAAAAAAAQMAAhEh/9oADAMBAAIRAxEAPwBcufDq9Y3Q/p3y8jRc+mX/AHMuThu0jwfbIyNcN36L6gkoJHLU5AUHsYZ4++m/rujNY6Xr3qbTRWqAGXjYjKEnPI/g86wa/U3U2z3IEuWVnp+krsZgGJB9/Ofvqhqq1tkFbLGuxOm6R3NJO0VSgHgFlz+dGqHvG47fvsle4oEDGAK6FfDAtnHto04SvIBczeCO70BLstqrKvqn5cBlH14bP51Ma9SWzVrQJGrmQrGgGe4ZGB9vp/WqdBMy0pnzljBIP851O3cR7ZXKEqXWPBXgg86zwTyZZA7MRq0kMjokx7Qx4B8aNeG/uEgtEoBhgGOTjzzo1J2UAz//2Q==
  """

  def tiny_png_path!(name \\ "tiny.png") do
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)
    command = System.find_executable("magick") || System.find_executable("convert")

    case command do
      nil ->
        raise "ImageMagick is required to build test fixtures"

      _ ->
        {_, 0} = System.cmd(command, ["-size", "2x2", "xc:#4f46e5", path], stderr_to_stdout: true)
    end

    path
  end

  def temp_dir!(name) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "rapid_tools_tests/#{name}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  def oriented_jpeg_path!(name \\ "oriented.jpg") do
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)

    binary =
      @oriented_jpeg_base64
      |> String.replace(~r/\s+/, "")
      |> Base.decode64!()

    File.write!(path, binary)
    path
  end

  def tiny_mp4_path!(name \\ "tiny.mp4") do
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)

    case System.find_executable("ffmpeg") do
      nil ->
        raise "ffmpeg is required to build video test fixtures"

      command ->
        {_, 0} =
          System.cmd(
            command,
            [
              "-y",
              "-f",
              "lavfi",
              "-i",
              "color=c=#0ea5e9:s=32x32:d=1",
              "-f",
              "lavfi",
              "-i",
              "anullsrc=channel_layout=stereo:sample_rate=44100",
              "-shortest",
              "-c:v",
              "libx264",
              "-pix_fmt",
              "yuv420p",
              "-c:a",
              "aac",
              path
            ],
            stderr_to_stdout: true
          )
    end

    path
  end

  def tiny_wav_path!(name \\ "tiny.wav") do
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)

    case System.find_executable("ffmpeg") do
      nil ->
        raise "ffmpeg is required to build audio test fixtures"

      command ->
        {_, 0} =
          System.cmd(
            command,
            [
              "-y",
              "-f",
              "lavfi",
              "-i",
              "sine=frequency=880:duration=1",
              "-c:a",
              "pcm_s16le",
              path
            ],
            stderr_to_stdout: true
          )
    end

    path
  end

  def audio_only_mp4_path!(name \\ "audio-only.mp4") do
    source_path = tiny_wav_path!("#{Path.rootname(name)}.wav")
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)

    case System.find_executable("ffmpeg") do
      nil ->
        raise "ffmpeg is required to build audio-only mp4 test fixtures"

      command ->
        {_, 0} =
          System.cmd(
            command,
            [
              "-y",
              "-i",
              source_path,
              "-c:a",
              "aac",
              "-vn",
              path
            ],
            stderr_to_stdout: true
          )
    end

    path
  end

  def video_only_mp4_path!(name \\ "video-only.mp4") do
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)

    case System.find_executable("ffmpeg") do
      nil ->
        raise "ffmpeg is required to build video-only mp4 test fixtures"

      command ->
        {_, 0} =
          System.cmd(
            command,
            [
              "-y",
              "-f",
              "lavfi",
              "-i",
              "testsrc=size=32x32:rate=1:duration=1",
              "-c:v",
              "libx264",
              "-pix_fmt",
              "yuv420p",
              "-an",
              path
            ],
            stderr_to_stdout: true
          )
    end

    path
  end

  def tiny_pdf_path!(name \\ "tiny.pdf") do
    png_path = tiny_png_path!("#{Path.rootname(name)}.png")
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)
    command = System.find_executable("magick") || System.find_executable("convert")

    case command do
      nil ->
        raise "ImageMagick is required to build PDF test fixtures"

      _ ->
        {_, 0} = System.cmd(command, [png_path, path], stderr_to_stdout: true)
    end

    path
  end

  def text_pdf_path!(name \\ "text.pdf") do
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)

    lines = [
      "%PDF-1.4",
      "1 0 obj",
      "<< /Type /Catalog /Pages 2 0 R >>",
      "endobj",
      "2 0 obj",
      "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
      "endobj",
      "3 0 obj",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
      "endobj"
    ]

    stream =
      [
        "BT",
        "/F1 24 Tf",
        "72 720 Td",
        "(Rapid Tools PDF Title) Tj",
        "0 -36 Td",
        "/F1 12 Tf",
        "(First paragraph for markdown extraction.) Tj",
        "0 -20 Td",
        "(Bullet one) Tj",
        "0 -20 Td",
        "(Bullet two) Tj",
        "ET"
      ]
      |> Enum.join("\n")

    object_4 = [
      "4 0 obj",
      "<< /Length #{byte_size(stream)} >>",
      "stream",
      stream,
      "endstream",
      "endobj"
    ]

    object_5 = [
      "5 0 obj",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      "endobj"
    ]

    objects = lines ++ object_4 ++ object_5

    {body, offsets, next_offset} =
      Enum.reduce(objects, {"", [0], 0}, fn line, {acc, acc_offsets, offset} ->
        chunk = line <> "\n"
        {acc <> chunk, acc_offsets ++ [offset], offset + byte_size(chunk)}
      end)

    xref_offset = next_offset

    xref =
      [
        "xref",
        "0 6",
        "0000000000 65535 f ",
        Enum.at(offsets, 1) |> format_xref_entry(),
        Enum.at(offsets, 4) |> format_xref_entry(),
        Enum.at(offsets, 7) |> format_xref_entry(),
        Enum.at(offsets, 10) |> format_xref_entry(),
        Enum.at(offsets, 15) |> format_xref_entry(),
        "trailer",
        "<< /Size 6 /Root 1 0 R >>",
        "startxref",
        Integer.to_string(xref_offset),
        "%%EOF"
      ]
      |> Enum.join("\n")

    File.write!(path, body <> xref)
    path
  end

  def docx_path!(name \\ "sample.docx") do
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)
    File.rm(path)

    {:ok, _zip_path} =
      :zip.create(
        String.to_charlist(path),
        [
          {~c"[Content_Types].xml", docx_content_types_xml()},
          {~c"_rels/.rels", docx_package_rels_xml()},
          {~c"word/document.xml", docx_document_xml()}
        ],
        []
      )

    path
  end

  defp format_xref_entry(offset) do
    offset
    |> Integer.to_string()
    |> String.pad_leading(10, "0")
    |> then(&"#{&1} 00000 n ")
  end

  defp docx_content_types_xml do
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """
  end

  defp docx_package_rels_xml do
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """
  end

  defp docx_document_xml do
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>
        <w:p>
          <w:r><w:t>Rapid Tools DOCX Title</w:t></w:r>
        </w:p>
        <w:p>
          <w:r><w:t>First paragraph for markdown extraction.</w:t></w:r>
        </w:p>
        <w:p>
          <w:r><w:t>Bullet one</w:t></w:r>
        </w:p>
        <w:p>
          <w:r><w:t>Bullet two</w:t></w:r>
        </w:p>
        <w:sectPr>
          <w:pgSz w:w="12240" w:h="15840"/>
        </w:sectPr>
      </w:body>
    </w:document>
    """
  end

  def tiny_ogg_path!(name \\ "tiny.ogg") do
    dir = Path.join(System.tmp_dir!(), "rapid_tools_test_fixtures")
    File.mkdir_p!(dir)

    path = Path.join(dir, name)

    case System.find_executable("ffmpeg") do
      nil ->
        raise "ffmpeg is required to build audio test fixtures"

      command ->
        {_, 0} =
          System.cmd(
            command,
            [
              "-y",
              "-f",
              "lavfi",
              "-i",
              "sine=frequency=660:duration=1",
              "-c:a",
              "libvorbis",
              path
            ],
            stderr_to_stdout: true
          )
    end

    path
  end
end
