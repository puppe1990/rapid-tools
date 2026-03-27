This repository contains `RapidTools`, a Phoenix LiveView application for batch media conversion.

## Product overview

- Root route: `/` for image conversion
- Extra tools:
  - `/video-converter`
  - `/audio-converter`
- Downloads:
  - `/downloads/:id`
  - `/downloads/batches/:id`

The app currently supports:

- Image conversion via ImageMagick: `png`, `jpg`, `webp`, `heic`, `avif`
- Video conversion via `ffmpeg`: `mp4`, `mov`, `webm`, `mkv`, `avi`
- Audio conversion via `ffmpeg`: `mp3`, `wav`, `ogg`, `aac`, `flac`

## Core workflow

- Each converter is a LiveView under `lib/rapid_tools_web/live/`
- Converted files are stored temporarily and registered in `RapidTools.ConversionStore`
- Batch downloads are generated as ZIP files by `RapidTools.ZipArchive`
- UI navigation between tools is duplicated per LiveView today; keep the three tool entries in sync when editing one screen

## Development rules

- Run `mix precommit` after completing changes
- Use the existing `Req` dependency for HTTP requests
- Prefer focused `mix test path/to/test.exs` while iterating, then run `mix precommit`
- If you change `config/*.exs`, restart the Phoenix server. Code reloading is not enough

## Environment requirements

- `ffmpeg` is required for video and audio conversion and related tests
- `magick` or `convert` from ImageMagick is required for image conversion and image fixture generation

## Phoenix and LiveView conventions

- Wrap LiveView templates with `<Layouts.app flash={@flash} ...>`
- Use `<.input>` for form fields and `to_form/2` in LiveViews
- Keep unique DOM ids on key elements because tests rely on them
- Use `<.link navigate={...}>` instead of deprecated LiveView navigation helpers
- Do not add inline `<script>` tags in HEEx templates

## Testing expectations

- Prefer testing LiveViews with `has_element?/2`, `element/2`, `render_change/2`, and `render_submit/2`
- Do not assert against entire raw HTML when a stable selector is available
- Add or update tests when routes, accepted upload types, or converter outputs change
- Media fixtures live in `test/support/image_fixtures.ex`

## Documentation

- Keep `README.md` aligned with the real supported routes and formats
- Keep `docs/rapid-tools-screenshot.png` up to date when the primary UI changes materially
- If the screenshot stops matching the product, regenerate it from a running local server before finishing
