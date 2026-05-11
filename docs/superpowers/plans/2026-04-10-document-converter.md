# Document Converter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the narrow PDF converter screen with a broader runtime-aware document converter that keeps the existing PDF flows and adds pragmatic office/text document conversion.

**Architecture:** Add a focused `RapidTools.DocumentConverter` backend that exposes supported modes from the local runtime, reuses `RapidTools.PdfConverter` for PDF/image work, and powers a new `RapidToolsWeb.DocumentConverterLive`. Update routing, shared navigation, tests, docs, and screenshot references to point to `/document-converter`.

**Tech Stack:** Phoenix LiveView, Elixir, `System.cmd/3`, LibreOffice `soffice`, macOS `textutil`, ImageMagick, ExUnit

---

### Task 1: Lock Runtime-Aware Backend Contract

**Files:**
- Create: `lib/rapid_tools/document_converter.ex`
- Create: `test/rapid_tools/document_converter_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule RapidTools.DocumentConverterTest do
  use ExUnit.Case, async: true

  alias RapidTools.DocumentConverter

  test "lists pdf and image modes plus runtime-backed document modes" do
    modes = DocumentConverter.supported_modes()

    assert "pdf_to_png" in modes
    assert "pdf_to_jpg" in modes
    assert "images_to_pdf" in modes
    assert Enum.any?(modes, &String.ends_with?(&1, "_to_pdf"))
  end

  test "reports accepted upload extensions from supported source formats" do
    accepts = DocumentConverter.accept_extensions()

    assert ".pdf" in accepts
    assert ".jpg" in accepts
    assert ".png" in accepts
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/rapid_tools/document_converter_test.exs`
Expected: FAIL with `RapidTools.DocumentConverter` undefined

- [ ] **Step 3: Write minimal implementation**

```elixir
defmodule RapidTools.DocumentConverter do
  @pdf_modes ~w(pdf_to_png pdf_to_jpg images_to_pdf)
  @pdf_accept ~w(.pdf .jpg .jpeg .png .webp)

  def supported_modes do
    @pdf_modes ++ office_modes()
  end

  def accept_extensions do
    (@pdf_accept ++ office_accept_extensions()) |> Enum.uniq()
  end

  defp office_modes do
    if soffice_available?(), do: ~w(docx_to_pdf odt_to_pdf rtf_to_pdf txt_to_pdf md_to_pdf html_to_pdf), else: []
  end

  defp office_accept_extensions do
    if soffice_available?(), do: ~w(.docx .odt .rtf .txt .md .html), else: []
  end

  defp soffice_available?, do: not is_nil(System.find_executable("soffice"))
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/rapid_tools/document_converter_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/rapid_tools/document_converter.ex test/rapid_tools/document_converter_test.exs
git commit -m "feat: add document converter backend contract"
```

### Task 2: Replace Route and Sidebar Entry

**Files:**
- Modify: `lib/rapid_tools_web/router.ex`
- Modify: `lib/rapid_tools_web/tool_navigation.ex`
- Test: `test/rapid_tools_web/live/route_locale_consistency_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
test "document converter route exposes document workflow copy" do
  {:ok, _view, html} = live(build_conn(), ~p"/document-converter")

  assert html =~ "Document workflow"
  refute html =~ "/pdf-converter"
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/rapid_tools_web/live/route_locale_consistency_test.exs`
Expected: FAIL because route and copy do not exist yet

- [ ] **Step 3: Write minimal implementation**

```elixir
# router.ex
live "/document-converter", DocumentConverterLive

# tool_navigation.ex
%{
  key: "document-converter",
  name: gettext("Document Converter"),
  blurb: gettext("Convert PDFs, docs and text files"),
  current: current == "document-converter",
  path: ~p"/document-converter"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/rapid_tools_web/live/route_locale_consistency_test.exs`
Expected: PASS or fail later only because LiveView not implemented yet

- [ ] **Step 5: Commit**

```bash
git add lib/rapid_tools_web/router.ex lib/rapid_tools_web/tool_navigation.ex test/rapid_tools_web/live/route_locale_consistency_test.exs
git commit -m "feat: wire document converter route and navigation"
```

### Task 3: Build the LiveView by Reusing PDF Flows

**Files:**
- Create: `lib/rapid_tools_web/live/document_converter_live.ex`
- Delete: `lib/rapid_tools_web/live/pdf_converter_live.ex`
- Create: `test/rapid_tools_web/live/document_converter_live_test.exs`
- Delete: `test/rapid_tools_web/live/pdf_converter_live_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
test "renders the document converter interface", %{conn: conn} do
  {:ok, view, html} = live(conn, ~p"/document-converter")

  assert has_element?(view, "form#document-converter-form")
  assert has_element?(view, "#document-convert-button")
  assert has_element?(view, "#document-upload-list")
  assert has_element?(view, "a[href=\"/document-converter\"]", "Document Converter")
  assert html =~ "Convert PDFs, documents and text files"
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/rapid_tools_web/live/document_converter_live_test.exs`
Expected: FAIL because the LiveView file does not exist

- [ ] **Step 3: Write minimal implementation**

```elixir
defmodule RapidToolsWeb.DocumentConverterLive do
  use RapidToolsWeb, :live_view

  alias RapidTools.DocumentConverter
  alias RapidTools.ConversionStore
  alias RapidTools.ZipArchive
  alias RapidToolsWeb.ToolNavigation

  # follow existing converter layout and event model
end
```

The implementation should:

- copy the established richer layout pattern from existing converter screens
- call `DocumentConverter.supported_modes/0` and `accept_extensions/0`
- keep `pdf_to_png`, `pdf_to_jpg`, and `images_to_pdf` working via the backend
- keep upload progress, remove-upload action, disabled submit on incomplete uploads, results, and ZIP packaging

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/rapid_tools_web/live/document_converter_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/rapid_tools_web/live/document_converter_live.ex test/rapid_tools_web/live/document_converter_live_test.exs
git rm lib/rapid_tools_web/live/pdf_converter_live.ex test/rapid_tools_web/live/pdf_converter_live_test.exs
git commit -m "feat: replace pdf converter screen with document converter"
```

### Task 4: Implement Office/Text Conversion Paths

**Files:**
- Modify: `lib/rapid_tools/document_converter.ex`
- Modify: `test/rapid_tools/document_converter_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
test "converts markdown to pdf when soffice is available" do
  source = Path.join(System.tmp_dir!(), "doc-converter-test.md")
  File.write!(source, "# Hello\n\nWorld\n")

  if System.find_executable("soffice") do
    assert {:ok, result} = DocumentConverter.convert(source, "md_to_pdf", output_dir: System.tmp_dir!())
    assert File.exists?(result.output_path)
    assert result.media_type == "application/pdf"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/rapid_tools/document_converter_test.exs`
Expected: FAIL because `convert/3` does not exist

- [ ] **Step 3: Write minimal implementation**

```elixir
def convert(source_path, mode, opts \\ []) do
  case mode do
    "pdf_to_png" -> PdfConverter.pdf_to_images(source_path, "png", opts)
    "pdf_to_jpg" -> PdfConverter.pdf_to_images(source_path, "jpg", opts)
    office_mode -> convert_with_soffice(source_path, office_mode, opts)
  end
end
```

Support only the source/target pairs actually enabled in `supported_modes/0`, and return normalized maps with:

- `output_path`
- `filename`
- `media_type`
- `target_format`

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/rapid_tools/document_converter_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/rapid_tools/document_converter.ex test/rapid_tools/document_converter_test.exs
git commit -m "feat: add runtime-backed document conversion modes"
```

### Task 5: Align Docs and Shared LiveView Assertions

**Files:**
- Modify: `README.md`
- Modify: `test/rapid_tools_web/live/image_converter_live_test.exs`
- Modify: `test/rapid_tools_web/live/audio_converter_live_test.exs`
- Modify: `test/rapid_tools_web/live/video_converter_live_test.exs`
- Modify: `test/rapid_tools_web/live/together_audios_live_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
assert has_element?(view, "a[href=\"/document-converter\"]", "Document Converter")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/rapid_tools_web/live/image_converter_live_test.exs test/rapid_tools_web/live/audio_converter_live_test.exs test/rapid_tools_web/live/video_converter_live_test.exs test/rapid_tools_web/live/together_audios_live_test.exs`
Expected: FAIL because the sidebar still points to `/pdf-converter`

- [ ] **Step 3: Write minimal implementation**

```markdown
- Document converter at `/document-converter`
```

Update the shared assertions to the new route/name.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/rapid_tools_web/live/image_converter_live_test.exs test/rapid_tools_web/live/audio_converter_live_test.exs test/rapid_tools_web/live/video_converter_live_test.exs test/rapid_tools_web/live/together_audios_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add README.md test/rapid_tools_web/live/image_converter_live_test.exs test/rapid_tools_web/live/audio_converter_live_test.exs test/rapid_tools_web/live/video_converter_live_test.exs test/rapid_tools_web/live/together_audios_live_test.exs
git commit -m "docs: align navigation and docs with document converter"
```

### Task 6: Verify Full Flow and Quality Gates

**Files:**
- Modify if needed: `docs/rapid-tools-screenshot.png`

- [ ] **Step 1: Run focused tests**

```bash
mix test test/rapid_tools/document_converter_test.exs \
  test/rapid_tools_web/live/document_converter_live_test.exs \
  test/rapid_tools_web/live/route_locale_consistency_test.exs
```

Expected: PASS

- [ ] **Step 2: Update screenshot if the main UI materially changed**

Run the local server, regenerate `docs/rapid-tools-screenshot.png`, and confirm the new document converter screen is represented if the previous screenshot is no longer accurate.

- [ ] **Step 3: Run precommit**

```bash
mix precommit
```

Expected: PASS

- [ ] **Step 4: Commit final polish**

```bash
git add docs/rapid-tools-screenshot.png
git commit -m "test: verify document converter rollout"
```
