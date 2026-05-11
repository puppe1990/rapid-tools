# PDF MD DOCX Roundtrip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add all bidirectional conversion pairs between `pdf`, `md`, and `docx` to `Document Converter`, while keeping runtime capability checks truthful and preserving the existing PDF utility flows.

**Architecture:** Extend `RapidTools.DocumentConverter` into a runtime-aware orchestrator with small helper paths for PDF extraction, markdown normalization, and DOCX generation. Keep the LiveView thin: mode list, upload validation, conversion dispatch, and results. Any DOCX writer logic that grows beyond a few functions should move into a focused helper module under `lib/rapid_tools/document_converter/`.

**Tech Stack:** Phoenix LiveView, Elixir, `ExtractousEx`, LibreOffice `soffice`, ZIP packaging, ExUnit

---

### Task 1: Lock Mode Matrix and Capability Gates

**Files:**
- Modify: `lib/rapid_tools/document_converter.ex`
- Modify: `test/rapid_tools/document_converter_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
test "supported_modes/0 exposes all directed pairs when dependencies are available" do
  modes = RapidTools.DocumentConverter.supported_modes()

  assert "pdf_to_md_clean" in modes
  assert "pdf_to_md_fidelity" in modes
  assert "pdf_to_docx" in modes
  assert "md_to_pdf" in modes
  assert "md_to_docx" in modes
  assert "docx_to_pdf" in modes
  assert "docx_to_md_clean" in modes
  assert "docx_to_md_fidelity" in modes
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/rapid_tools/document_converter_test.exs`
Expected: FAIL because the missing modes are not yet exposed

- [ ] **Step 3: Write minimal implementation**

Add explicit capability groups and mode lists in `lib/rapid_tools/document_converter.ex`:

```elixir
@pdf_markdown_modes ~w(pdf_to_md_clean pdf_to_md_fidelity)
@pdf_docx_modes ~w(pdf_to_docx)
@markdown_modes ~w(md_to_pdf md_to_docx)
@docx_modes ~w(docx_to_pdf docx_to_md_clean docx_to_md_fidelity)
```

Expose them only when the required backend is loaded and callable.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/rapid_tools/document_converter_test.exs`
Expected: PASS for mode visibility

- [ ] **Step 5: Commit**

```bash
git add lib/rapid_tools/document_converter.ex test/rapid_tools/document_converter_test.exs
git commit -m "feat: expose pdf md docx roundtrip mode matrix"
```

### Task 2: Implement `md -> pdf` and `md -> docx`

**Files:**
- Modify: `lib/rapid_tools/document_converter.ex`
- Create if needed: `lib/rapid_tools/document_converter/docx_writer.ex`
- Modify: `test/rapid_tools/document_converter_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
test "converts markdown to docx" do
  source_dir = ImageFixtures.temp_dir!("markdown-to-docx")
  source_path = Path.join(source_dir, "sample.md")
  output_dir = ImageFixtures.temp_dir!("markdown-to-docx-output")

  File.write!(source_path, "# Heading\n\nParagraph\n\n- item one\n- item two\n")

  assert {:ok, result} =
           DocumentConverter.convert(source_path, "md_to_docx", output_dir: output_dir)

  assert result.media_type ==
           "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
  assert String.ends_with?(result.output_path, ".docx")
  assert File.exists?(result.output_path)
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/rapid_tools/document_converter_test.exs`
Expected: FAIL because `md_to_docx` is not implemented

- [ ] **Step 3: Write minimal implementation**

Implement:

- markdown to HTML/document conversion
- markdown to DOCX generation
- markdown to PDF via the existing office export path

Keep the generated metadata shape identical to other converter outputs.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/rapid_tools/document_converter_test.exs`
Expected: PASS for markdown export tests

- [ ] **Step 5: Commit**

```bash
git add lib/rapid_tools/document_converter.ex lib/rapid_tools/document_converter/docx_writer.ex test/rapid_tools/document_converter_test.exs
git commit -m "feat: add markdown to pdf and docx conversion"
```

### Task 3: Implement `docx -> pdf` and `docx -> md`

**Files:**
- Modify: `lib/rapid_tools/document_converter.ex`
- Modify: `test/rapid_tools/document_converter_test.exs`
- Modify if needed: `test/support/image_fixtures.ex`

- [ ] **Step 1: Write the failing test**

```elixir
test "converts docx to markdown in clean mode" do
  source_path = ImageFixtures.docx_path!("docx-clean-source.docx")
  output_dir = ImageFixtures.temp_dir!("docx-to-md-clean")

  assert {:ok, result} =
           DocumentConverter.convert(source_path, "docx_to_md_clean", output_dir: output_dir)

  markdown = File.read!(result.output_path)
  assert markdown =~ "Heading"
  assert markdown =~ "Paragraph"
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/rapid_tools/document_converter_test.exs`
Expected: FAIL because docx extraction paths are missing

- [ ] **Step 3: Write minimal implementation**

Use the document extraction backend for `.docx` and produce:

- `docx_to_pdf` via office export
- `docx_to_md_clean` via normalized text extraction
- `docx_to_md_fidelity` via structured extraction

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/rapid_tools/document_converter_test.exs`
Expected: PASS for DOCX conversion tests

- [ ] **Step 5: Commit**

```bash
git add lib/rapid_tools/document_converter.ex test/rapid_tools/document_converter_test.exs test/support/image_fixtures.ex
git commit -m "feat: add docx to pdf and markdown conversion"
```

### Task 4: Implement `pdf -> docx`

**Files:**
- Modify: `lib/rapid_tools/document_converter.ex`
- Modify if needed: `lib/rapid_tools/document_converter/docx_writer.ex`
- Modify: `test/rapid_tools/document_converter_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
test "converts pdf to docx" do
  source_path = ImageFixtures.text_pdf_path!("pdf-to-docx-source.pdf")
  output_dir = ImageFixtures.temp_dir!("pdf-to-docx")

  assert {:ok, result} =
           DocumentConverter.convert(source_path, "pdf_to_docx", output_dir: output_dir)

  assert String.ends_with?(result.output_path, ".docx")
  assert File.exists?(result.output_path)
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/rapid_tools/document_converter_test.exs`
Expected: FAIL because the PDF to DOCX path is missing

- [ ] **Step 3: Write minimal implementation**

Reuse the PDF extraction backend to obtain normalized content, then emit a DOCX document with:

- heading for the title when detected
- paragraph blocks
- basic list handling where obvious

Do not attempt visual layout reconstruction.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/rapid_tools/document_converter_test.exs`
Expected: PASS for PDF to DOCX conversion

- [ ] **Step 5: Commit**

```bash
git add lib/rapid_tools/document_converter.ex lib/rapid_tools/document_converter/docx_writer.ex test/rapid_tools/document_converter_test.exs
git commit -m "feat: add pdf to docx conversion"
```

### Task 5: Expand LiveView Mode List and UX Copy

**Files:**
- Modify: `lib/rapid_tools_web/live/document_converter_live.ex`
- Modify: `test/rapid_tools_web/live/document_converter_live_test.exs`
- Modify: `priv/gettext/default.pot`
- Modify: `priv/gettext/en/LC_MESSAGES/default.po`
- Modify: `priv/gettext/pt_BR/LC_MESSAGES/default.po`

- [ ] **Step 1: Write the failing test**

```elixir
test "renders all primary pdf md docx roundtrip modes", %{conn: conn} do
  {:ok, _view, html} = live(conn, ~p"/document-converter")

  assert html =~ "PDF to DOCX"
  assert html =~ "Markdown to DOCX"
  assert html =~ "DOCX to PDF"
  assert html =~ "DOCX to Markdown (Clean)"
  assert html =~ "DOCX to Markdown (Fidelity)"
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/rapid_tools_web/live/document_converter_live_test.exs`
Expected: FAIL because the new options are not rendered yet

- [ ] **Step 3: Write minimal implementation**

Update:

- mode options
- hero/support copy
- info panel copy
- runtime-aware visibility

Then extract and merge gettext strings:

```bash
mix gettext.extract --merge
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/rapid_tools_web/live/document_converter_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/rapid_tools_web/live/document_converter_live.ex priv/gettext/default.pot priv/gettext/en/LC_MESSAGES/default.po priv/gettext/pt_BR/LC_MESSAGES/default.po test/rapid_tools_web/live/document_converter_live_test.exs
git commit -m "feat: expand document converter roundtrip ui"
```

### Task 6: Add Runtime-Safe Failure Handling

**Files:**
- Modify: `lib/rapid_tools/document_converter.ex`
- Modify: `lib/rapid_tools_web/live/document_converter_live.ex`
- Modify: `test/rapid_tools/document_converter_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
test "returns a normal error when a stale mode is submitted without backend support" do
  source_path = ImageFixtures.text_pdf_path!("stale-pdf-mode.pdf")
  output_dir = ImageFixtures.temp_dir!("stale-mode")

  assert {:error, _reason} =
           DocumentConverter.convert(source_path, "pdf_to_md_clean", output_dir: output_dir)
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/rapid_tools/document_converter_test.exs`
Expected: FAIL if stale mode handling is not normalized

- [ ] **Step 3: Write minimal implementation**

Ensure stale or unavailable modes return tagged errors rather than crashing. Keep the LiveView flash behavior consistent.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/rapid_tools/document_converter_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/rapid_tools/document_converter.ex lib/rapid_tools_web/live/document_converter_live.ex test/rapid_tools/document_converter_test.exs
git commit -m "fix: harden document converter runtime fallback"
```

### Task 7: Update README and Screenshot

**Files:**
- Modify: `README.md`
- Modify if needed: `docs/rapid-tools-screenshot.png`

- [ ] **Step 1: Write the docs delta**

Update the supported document workflows section to reflect all `pdf/md/docx` pairs and note that some modes depend on the runtime backends being available.

- [ ] **Step 2: Regenerate screenshot if UI changed materially**

Open the local app and capture the updated `Document Converter` UI into `docs/rapid-tools-screenshot.png`.

- [ ] **Step 3: Commit**

```bash
git add README.md docs/rapid-tools-screenshot.png
git commit -m "docs: update document roundtrip workflows"
```

### Task 8: Final Verification

**Files:**
- No planned source changes; fix only if verification reveals a real issue

- [ ] **Step 1: Run focused roundtrip tests**

```bash
mix test test/rapid_tools/document_converter_test.exs test/rapid_tools_web/live/document_converter_live_test.exs
```

Expected: PASS

- [ ] **Step 2: Run full quality gate**

```bash
mix precommit
```

Expected: PASS

- [ ] **Step 3: Commit verification fixes if needed**

```bash
git add .
git commit -m "test: verify pdf md docx roundtrip rollout"
```
