# Document Converter Design

## Goal

Replace the narrow `/pdf-converter` tool with a broader `/document-converter` LiveView that covers pragmatic document conversion needs while preserving the current PDF workflows already present in RapidTools.

The new tool should:

- absorb the current PDF conversion use cases
- follow the same richer layout and interaction model used by the other converter tools
- expose only conversion modes that can be implemented reliably in the current environment
- keep a single, clear navigation entry for document-related work

## Scope

### In scope for V1

- New route: `/document-converter`
- Remove `/pdf-converter` as a user-facing tool and route
- Shared sidebar navigation updated to reference `Document Converter`
- Preserve current PDF flows:
  - `pdf -> png`
  - `pdf -> jpg`
  - `images -> pdf`
- Add document upload support for:
  - `pdf`
  - `docx`
  - `odt`
  - `rtf`
  - `txt`
  - `md`
  - `html`
- Add pragmatic output targets limited to formats the runtime can support consistently
- Update tests, README, and screenshot if the primary UI changes materially

### Out of scope for V1

- `xlsx`, `csv`, `pptx`, `key`, `pages`, and spreadsheet/presentation-specific conversion
- OCR
- merging mixed PDFs and office documents into one output file unless implementation is already reliable
- remote conversion services

## Product Behavior

### User experience

The new `Document Converter` screen should use the same structural pattern as the richer converter screens:

- left sidebar with shared tool navigation
- hero block with badge, title, short description, and supporting copy
- main upload/conversion card
- scrollable upload list with per-file progress and remove action
- disabled submit while uploads are incomplete
- right-side info/results panel

The page should have its own visual identity and must not reuse the same accent palette as image, video, or audio converters.

### Supported interactions

Users can:

- upload one or more supported files
- select a conversion mode
- wait for uploads to finish
- run batch conversion when allowed by the selected mode
- download individual outputs
- download a ZIP when multiple outputs are produced

### Mode rules

The UI should present only reliable modes. V1 should support these groups:

1. Existing PDF/image workflows:
   - `PDF to PNG`
   - `PDF to JPG`
   - `Images to PDF`

2. Text/document workflows, gated by runtime support:
   - document-like inputs to `PDF`
   - document-like inputs to `HTML`
   - document-like inputs to `TXT`
   - markdown-compatible inputs to `MD` only where round-tripping is straightforward

If a source/target pair is not implemented safely, it must not appear as a selectable mode.

## Technical Design

### Routing and navigation

- Add `RapidToolsWeb.DocumentConverterLive`
- Add `live "/document-converter", DocumentConverterLive`
- Remove `live "/pdf-converter", PdfConverterLive`
- Replace the sidebar entry metadata from `PDF Converter` to `Document Converter`

### LiveView strategy

Create a new LiveView rather than mutating the current PDF LiveView in place.

Reasons:

- keeps document semantics clear
- avoids overloading the old module name with new responsibilities
- makes it easier to move only the reusable conversion helpers
- reduces confusion in tests and navigation

`DocumentConverterLive` should reuse the established patterns from the other converter LiveViews:

- upload configuration in `mount/3`
- `validate`, `cancel-upload`, and `convert` events
- upload state summaries and empty states
- conversion results stored in `RapidTools.ConversionStore`
- ZIP packaging through `RapidTools.ZipArchive`

### Conversion backend

Introduce a dedicated backend module for document conversions, separate from the LiveView.

Candidate module:

- `RapidTools.DocumentConverter`

Responsibilities:

- declare supported input/output combinations
- normalize formats and mode names
- route PDF/image conversions through the current PDF conversion functionality where appropriate
- route text/document conversions through an available local toolchain
- return normalized result maps used by the LiveView

`RapidTools.PdfConverter` should remain as a focused low-level helper for:

- `pdf_to_images/3`
- `images_to_pdf/2`

That keeps the current PDF implementation reusable inside the new document converter without preserving the old screen.

### Runtime support policy

The implementation must detect the available local toolchain and expose only modes that can actually run.

Preferred behavior:

- use locally available CLI tools already present in the environment
- if office-document conversion tooling is missing, keep PDF/image modes working and hide unsupported office modes
- do not render options in the UI that always fail in the current runtime

This keeps the feature pragmatic and avoids false promises.

### Accepted files

The LiveView upload accept list should include only the source extensions supported by the current runtime policy.

Base list for V1 design:

- `.pdf`
- `.jpg`
- `.jpeg`
- `.png`
- `.webp`
- `.docx`
- `.odt`
- `.rtf`
- `.txt`
- `.md`
- `.html`

If runtime detection makes some office formats unavailable, the UI copy and acceptance list should remain aligned.

## Error Handling

- If no files are uploaded, show the existing style of actionable flash message.
- If uploads are still running, block conversion with the current interaction model.
- If an unsupported conversion is requested due to stale UI state, fail safely with a clear flash message.
- If one file in a batch fails, preserve successful outputs where practical and communicate partial failure explicitly.
- If ZIP generation fails, keep individual downloads available and surface the ZIP failure separately.

## Testing

Add or update tests for:

- route renders at `/document-converter`
- sidebar points to `/document-converter`
- upload accept behavior for supported document types
- default mode and visible mode labels
- existing PDF upload/render flow still works through the new screen
- removal of `/pdf-converter` route coverage

Prefer focused LiveView tests using stable selectors.

## Documentation

- update `README.md` routes and supported formats
- update any references to `PDF Converter` that are now `Document Converter`
- regenerate `docs/rapid-tools-screenshot.png` if the primary UI changes materially

## Open implementation check

Before code changes, verify which local document-conversion toolchain is available and restrict the final mode matrix accordingly. The UI, tests, and README must describe the actual supported formats, not the aspirational set.
