# PDF MD DOCX Roundtrip Design

## Goal

Make `Document Converter` the canonical tool for bidirectional conversion between `pdf`, `md`, and `docx`, covering every directed pair between the three formats.

Required pairs:

- `pdf -> md`
- `pdf -> docx`
- `md -> pdf`
- `md -> docx`
- `docx -> pdf`
- `docx -> md`

## Scope

### In scope for V1

- Add all six directed conversion pairs above
- Keep explicit mode selection in the UI
- Keep the existing `PDF -> PNG`, `PDF -> JPG`, and `Images -> PDF` flows available as secondary document utilities
- Expose only modes that are actually supported by the local runtime
- Preserve two markdown quality profiles where they materially help:
  - `Clean`
  - `Fidelity`

### Out of scope for V1

- Spreadsheet or presentation formats
- OCR-first scanned PDF recovery
- full visual/layout fidelity guarantees for `pdf -> docx`
- embedded asset packaging beyond what is necessary for a usable markdown/docx result

## Product Behavior

### Primary conversion modes

The UI should expose these modes when supported:

- `PDF to Markdown (Clean)`
- `PDF to Markdown (Fidelity)`
- `PDF to DOCX`
- `Markdown to PDF`
- `Markdown to DOCX`
- `DOCX to PDF`
- `DOCX to Markdown (Clean)`
- `DOCX to Markdown (Fidelity)`

Secondary modes may remain:

- `PDF to PNG`
- `PDF to JPG`
- `Images to PDF`

### Expected output quality

- `md -> pdf`: strong
- `md -> docx`: strong
- `docx -> pdf`: strong
- `docx -> md`: good, with some formatting loss depending on source
- `pdf -> md`: good for text and structure, limited for complex layouts
- `pdf -> docx`: useful and editable, but not high-fidelity for visually complex PDFs

The product should communicate this implicitly via clean mode names and supporting copy, not via technical jargon.

## Technical Design

### Backend module

Continue using `RapidTools.DocumentConverter` as the orchestration layer.

Responsibilities:

- list supported modes based on runtime capability
- validate source extension per mode
- delegate each conversion to the appropriate implementation path
- normalize output metadata for the LiveView

### Runtime capability policy

Modes must only be shown when the required backend is truly available in the running BEAM.

Capability groups:

- PDF markdown extraction backend
- DOCX/PDF office export backend
- markdown/docx generation backend

This avoids the stale-UI/runtime mismatch that previously caused LiveView crashes.

### Conversion strategy by pair

#### `pdf -> md`

Use a document extraction backend that can return:

- plain extracted text for `Clean`
- structured/XML-like output for `Fidelity`

`Clean` should normalize paragraphs and headings for downstream editing and LLM use.

`Fidelity` should preserve more literal block ordering, page markers, and list-like structure where possible.

#### `pdf -> docx`

Use the same PDF extraction backend to produce normalized structured text, then write a `.docx` document from that structured representation.

The result is semantic/editable, not visually faithful.

#### `md -> pdf`

Render markdown into an intermediate document/HTML form and export to PDF through the document backend already used for office export.

#### `md -> docx`

Convert markdown into a structured document form and write a `.docx` output directly.

#### `docx -> pdf`

Export via the office document backend.

#### `docx -> md`

Extract structured content from `.docx` and produce:

- `Clean`: normalized markdown for editing/search/LLM workflows
- `Fidelity`: more literal block preservation and stronger heading/list handling

## File Boundaries

Expected implementation units:

- `lib/rapid_tools/document_converter.ex`
  - orchestration and capability gating
- `lib/rapid_tools/document_converter/*` helper modules if needed
  - markdown normalization
  - docx generation
  - extractor wrappers
- `lib/rapid_tools_web/live/document_converter_live.ex`
  - mode list and UI copy
- tests for backend and LiveView behavior

If docx writing logic becomes nontrivial, it should move out of the main converter module into a focused helper instead of inflating one file.

## Error Handling

- Unsupported modes must never appear when the runtime backend is unavailable
- If a stale form submits an unavailable mode, return a normal conversion error instead of crashing
- If a conversion backend raises or returns invalid output, map it to a user-facing flash and preserve the LiveView process
- Batch ZIP behavior should remain unchanged

## Testing

Add or update coverage for:

- mode visibility for all supported pairs
- `pdf -> md clean`
- `pdf -> md fidelity`
- `pdf -> docx`
- `md -> pdf`
- `md -> docx`
- `docx -> pdf`
- `docx -> md clean`
- `docx -> md fidelity`
- stale backend capability fallback does not crash LiveView

The test fixture set must include:

- textual PDF fixture
- markdown fixture
- docx fixture

## Documentation

Update `README.md` to describe the `pdf/md/docx` roundtrip flows as the primary document feature set.

If the main UI changes materially again, regenerate `docs/rapid-tools-screenshot.png`.

## Constraints

- Prefer pragmatic quality over fake fidelity
- Do not promise layout-perfect `pdf -> docx`
- Keep UI copy aligned with actual runtime capability
- Restarting the Phoenix server is required whenever dependency/config changes affect runtime capabilities
