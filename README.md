# RapidTools

RapidTools is a Phoenix LiveView app for batch image, video, and audio conversion with individual downloads and ZIP bundles.

## Preview

![RapidTools screenshot](docs/rapid-tools-screenshot.png)

## Available tools

- Image converter at `/`
- Video converter at `/video-converter`
- Audio converter at `/audio-converter`

## Supported formats

### Image output

- `PNG`
- `JPG`
- `WEBP`
- `HEIC`
- `AVIF`

### Video output

- `MP4`
- `MOV`
- `WEBM`
- `MKV`
- `AVI`

### Audio output

- `MP3`
- `WAV`
- `OGG`
- `AAC`
- `FLAC`

## Features

- Batch upload and conversion per tool
- Individual file download after conversion
- ZIP package download for converted batches
- Phoenix LiveView interface with dedicated screens for image, video, and audio workflows

## Requirements

- Elixir and Erlang compatible with the versions in `mix.exs`
- `ffmpeg` installed locally for audio and video conversion
- ImageMagick installed locally as `magick` or `convert` for image conversion

## Development

```bash
mix setup
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000).

If you change any file under `config/`, restart the server instead of relying on code reloading.

## Test

```bash
mix precommit
```

For focused iteration:

```bash
mix test test/rapid_tools/audio_converter_test.exs
mix test test/rapid_tools_web/live/audio_converter_live_test.exs
```
