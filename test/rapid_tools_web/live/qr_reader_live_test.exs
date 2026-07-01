defmodule RapidToolsWeb.QrReaderLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  test "renders the QR reader interface", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/qr-reader")

    assert has_element?(view, "form#qr-reader-form")
    assert has_element?(view, "#qr-reader-read-button")
    assert has_element?(view, "#qr-reader-result")
    assert has_element?(view, "#qr-reader-camera")
    assert has_element?(view, "a[href=\"/qr-reader\"]", "QR Reader")
    assert html =~ "Read QR codes from images or your camera"
  end

  test "switches between upload and camera modes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/qr-reader")

    assert has_element?(view, "#qr-reader-upload-panel")
    refute has_element?(view, "#qr-reader-camera-panel:not(.hidden)")

    render_click(view, "set-mode", %{"mode" => "camera"})

    assert has_element?(view, "#qr-reader-camera-panel:not(.hidden)")
    refute has_element?(view, "#qr-reader-upload-panel:not(.hidden)")
  end

  test "decodes a QR code from an uploaded image", %{conn: conn} do
    source_path = ImageFixtures.qr_png_path!("https://rapid.tools/qr-test", "qr-live-decode.png")
    {:ok, view, _html} = live(conn, ~p"/qr-reader")

    upload =
      file_input(view, "#qr-reader-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "sample-qr.png",
          content: File.read!(source_path),
          type: "image/png"
        }
      ])

    render_upload(upload, "sample-qr.png")

    rendered =
      view
      |> form("#qr-reader-form")
      |> render_submit()

    assert rendered =~ "https://rapid.tools/qr-test"
    assert has_element?(view, "#qr-reader-result", "https://rapid.tools/qr-test")
    assert rendered =~ "upload"
  end

  test "shows an error when reading without an upload", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/qr-reader")

    rendered =
      view
      |> form("#qr-reader-form")
      |> render_submit()

    assert rendered =~ "Select an image before reading the QR code"
  end

  test "shows an error when the uploaded image has no QR code", %{conn: conn} do
    source_path = ImageFixtures.tiny_png_path!("qr-live-no-code.png")
    {:ok, view, _html} = live(conn, ~p"/qr-reader")

    upload =
      file_input(view, "#qr-reader-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "plain.png",
          content: File.read!(source_path),
          type: "image/png"
        }
      ])

    render_upload(upload, "plain.png")

    rendered =
      view
      |> form("#qr-reader-form")
      |> render_submit()

    assert rendered =~ "No QR code was found in the uploaded image"
  end

  test "disables read button until upload is complete", %{conn: conn} do
    source_path =
      ImageFixtures.qr_png_path!("https://rapid.tools/qr-test", "qr-live-progress.png")

    {:ok, view, _html} = live(conn, ~p"/qr-reader")

    assert has_element?(view, "#qr-reader-read-button[disabled]")

    upload =
      file_input(view, "#qr-reader-form", :image, [
        %{
          last_modified: 1_711_000_000_000,
          name: "sample-qr.png",
          content: File.read!(source_path),
          type: "image/png"
        }
      ])

    render_upload(upload, "sample-qr.png")
    refute has_element?(view, "#qr-reader-read-button[disabled]")
  end

  test "stores camera scan results in the result panel", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/qr-reader")

    rendered = render_hook(view, "scan-result", %{"text" => "camera-payload"})

    assert rendered =~ "camera-payload"
    assert has_element?(view, "#qr-reader-result", "camera-payload")
    assert rendered =~ "camera"
  end

  test "clears a stored result", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/qr-reader")

    render_hook(view, "scan-result", %{"text" => "camera-payload"})
    rendered = render_click(view, "clear-result")

    assert rendered =~ "No QR code read yet"
    refute rendered =~ "camera-payload"
  end

  test "shows copy hint when a result is available", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/qr-reader")

    rendered = render_hook(view, "scan-result", %{"text" => "camera-payload"})

    assert has_element?(view, "#qr-reader-copy-hint")
    assert rendered =~ "Select the decoded text and copy it"
  end

  test "shows unavailable upload card when zbar is missing", %{conn: conn} do
    with_zbar_available(false, fn ->
      {:ok, _view, html} = live(conn, ~p"/qr-reader")

      assert html =~ "Upload decoding is unavailable"
      assert html =~ "Install zbar"
    end)
  end

  defp with_zbar_available(available?, fun) do
    original = Application.get_env(:rapid_tools, :qr_reader_available)

    Application.put_env(:rapid_tools, :qr_reader_available, available?)

    try do
      fun.()
    after
      if is_nil(original) do
        Application.delete_env(:rapid_tools, :qr_reader_available)
      else
        Application.put_env(:rapid_tools, :qr_reader_available, original)
      end
    end
  end
end
