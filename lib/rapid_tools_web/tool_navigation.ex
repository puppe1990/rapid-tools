defmodule RapidToolsWeb.ToolNavigation do
  use Phoenix.VerifiedRoutes,
    endpoint: RapidToolsWeb.Endpoint,
    router: RapidToolsWeb.Router,
    statics: RapidToolsWeb.static_paths()

  def tools(current) do
    [
      %{
        name: "Image Converter",
        blurb: "Batch image conversion",
        current: current == "image",
        path: ~p"/"
      },
      %{
        name: "Video Converter",
        blurb: "Convert MP4, MOV, WEBM, MKV and AVI",
        current: current == "video",
        path: ~p"/video-converter"
      },
      %{
        name: "Audio Converter",
        blurb: "Convert MP3, WAV, OGG, AAC and FLAC",
        current: current == "audio",
        path: ~p"/audio-converter"
      },
      %{
        name: "Together Audios",
        blurb: "Join multiple audio files into one track",
        current: current == "together-audios",
        path: ~p"/together-audios"
      }
    ]
  end
end
