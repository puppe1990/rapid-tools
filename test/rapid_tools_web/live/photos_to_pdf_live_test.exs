defmodule RapidToolsWeb.PhotosToPdfLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  test "renders the photos to pdf interface", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/photos-to-pdf")

    assert has_element?(view, "form#photos-to-pdf-form")
    assert has_element?(view, "#photos-to-pdf-button")
    assert has_element?(view, "#photos-to-pdf-upload-list")
    assert has_element?(view, "#photos-to-pdf-form .phx-submit-loading\\:flex")
    assert has_element?(view, "a[href=\"/photos-to-pdf\"]", "Photos to PDF")
    assert render(view) =~ "Photo layout"
    assert render(view) =~ "Photos to PDF"
    assert render(view) =~ "No photo selected yet."
    assert render(view) =~ "Reorder the queue with the arrows to define the PDF page order."
  end

  test "allows reordering uploaded photos before creating the pdf", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_png_path!("photos-to-pdf-reorder-1.png")
    source_path_2 = ImageFixtures.tiny_png_path!("photos-to-pdf-reorder-2.png")
    {:ok, view, _html} = live(conn, ~p"/photos-to-pdf")

    upload =
      file_input(view, "#photos-to-pdf-form", :image, [
        %{
          last_modified: 1_711_000_000_010,
          name: "first.png",
          content: File.read!(source_path_1),
          type: "image/png"
        },
        %{
          last_modified: 1_711_000_000_011,
          name: "second.png",
          content: File.read!(source_path_2),
          type: "image/png"
        }
      ])

    render_upload(upload, "first.png")

    initial_render = render(view)

    assert text_position(initial_render, "first.png") <
             text_position(initial_render, "second.png")

    reordered_render =
      view
      |> element("button[aria-label=\"Move first.png down\"]")
      |> render_click()

    assert text_position(reordered_render, "second.png") <
             text_position(reordered_render, "first.png")
  end

  test "creates a single pdf from uploaded photos", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_png_path!("photos-to-pdf-build-1.png")
    source_path_2 = ImageFixtures.tiny_png_path!("photos-to-pdf-build-2.png")
    {:ok, view, _html} = live(conn, ~p"/photos-to-pdf")

    upload_1 =
      file_input(view, "#photos-to-pdf-form", :image, [
        %{
          last_modified: 1_711_000_000_012,
          name: "invoice-1.png",
          content: File.read!(source_path_1),
          type: "image/png"
        }
      ])

    upload_2 =
      file_input(view, "#photos-to-pdf-form", :image, [
        %{
          last_modified: 1_711_000_000_013,
          name: "invoice-2.png",
          content: File.read!(source_path_2),
          type: "image/png"
        }
      ])

    render_upload(upload_1, "invoice-1.png")
    render_upload(upload_2, "invoice-2.png")

    rendered =
      view
      |> form("#photos-to-pdf-form")
      |> render_submit()

    assert rendered =~ "combined-images.pdf"
    assert rendered =~ "2 photos turned into a single PDF"
    assert rendered =~ "Download PDF"
    assert rendered =~ "/downloads/"
  end

  test "allows generating a second pdf with a new batch in the same session", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_png_path!("photos-to-pdf-second-run-1.png")
    source_path_2 = ImageFixtures.tiny_png_path!("photos-to-pdf-second-run-2.png")
    source_path_3 = ImageFixtures.tiny_png_path!("photos-to-pdf-second-run-3.png")
    source_path_4 = ImageFixtures.tiny_png_path!("photos-to-pdf-second-run-4.png")
    {:ok, view, _html} = live(conn, ~p"/photos-to-pdf")

    first_upload_1 =
      file_input(view, "#photos-to-pdf-form", :image, [
        %{
          last_modified: 1_711_000_000_020,
          name: "batch-a-1.png",
          content: File.read!(source_path_1),
          type: "image/png"
        }
      ])

    first_upload_2 =
      file_input(view, "#photos-to-pdf-form", :image, [
        %{
          last_modified: 1_711_000_000_021,
          name: "batch-a-2.png",
          content: File.read!(source_path_2),
          type: "image/png"
        }
      ])

    render_upload(first_upload_1, "batch-a-1.png")
    render_upload(first_upload_2, "batch-a-2.png")

    first_render =
      view
      |> form("#photos-to-pdf-form")
      |> render_submit()

    assert first_render =~ "batch-a-1.png"
    assert first_render =~ "batch-a-2.png"
    assert first_render =~ "Download PDF"

    second_upload_1 =
      file_input(view, "#photos-to-pdf-form", :image, [
        %{
          last_modified: 1_711_000_000_022,
          name: "batch-b-1.png",
          content: File.read!(source_path_3),
          type: "image/png"
        }
      ])

    second_upload_2 =
      file_input(view, "#photos-to-pdf-form", :image, [
        %{
          last_modified: 1_711_000_000_023,
          name: "batch-b-2.png",
          content: File.read!(source_path_4),
          type: "image/png"
        }
      ])

    render_upload(second_upload_1, "batch-b-1.png")
    render_upload(second_upload_2, "batch-b-2.png")

    second_render =
      view
      |> form("#photos-to-pdf-form")
      |> render_submit()

    assert second_render =~ "batch-b-1.png"
    assert second_render =~ "batch-b-2.png"
    assert second_render =~ "Download PDF"
  end

  defp text_position(rendered, text) do
    case :binary.match(rendered, text) do
      {position, _length} -> position
      :nomatch -> raise "expected to find #{inspect(text)} in rendered output"
    end
  end
end
