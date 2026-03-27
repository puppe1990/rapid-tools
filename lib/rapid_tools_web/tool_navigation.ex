defmodule RapidToolsWeb.ToolNavigation do
  use Phoenix.VerifiedRoutes,
    endpoint: RapidToolsWeb.Endpoint,
    router: RapidToolsWeb.Router,
    statics: RapidToolsWeb.static_paths()

  def tools(current) do
    [
      %{
        key: "image",
        name: "Image Converter",
        blurb: "Batch image conversion",
        current: current == "image",
        path: ~p"/",
        current_class:
          "border-orange-300 bg-orange-50 shadow-[inset_0_1px_0_rgba(255,255,255,0.9)]",
        idle_class: "border-slate-200 bg-white hover:border-orange-200 hover:bg-orange-50/40",
        dot_class: "bg-orange-500",
        name_class: "text-orange-800",
        blurb_class: "text-orange-700/80"
      },
      %{
        key: "video",
        name: "Video Converter",
        blurb: "Convert MP4, MOV, WEBM, MKV and AVI",
        current: current == "video",
        path: ~p"/video-converter",
        current_class:
          "border-indigo-300 bg-indigo-50 shadow-[inset_0_1px_0_rgba(255,255,255,0.9)]",
        idle_class: "border-slate-200 bg-white hover:border-indigo-200 hover:bg-indigo-50/40",
        dot_class: "bg-indigo-500",
        name_class: "text-indigo-800",
        blurb_class: "text-indigo-700/80"
      },
      %{
        key: "audio",
        name: "Audio Converter",
        blurb: "Convert MP3, WAV, OGG, AAC and FLAC",
        current: current == "audio",
        path: ~p"/audio-converter",
        current_class:
          "border-emerald-300 bg-emerald-50 shadow-[inset_0_1px_0_rgba(255,255,255,0.9)]",
        idle_class: "border-slate-200 bg-white hover:border-emerald-200 hover:bg-emerald-50/40",
        dot_class: "bg-emerald-500",
        name_class: "text-emerald-800",
        blurb_class: "text-emerald-700/80"
      },
      %{
        key: "together-audios",
        name: "Together Audios",
        blurb: "Join multiple audio files into one track",
        current: current == "together-audios",
        path: ~p"/together-audios",
        current_class:
          "border-amber-300 bg-amber-50 shadow-[inset_0_1px_0_rgba(255,255,255,0.9)]",
        idle_class: "border-slate-200 bg-white hover:border-amber-200 hover:bg-amber-50/40",
        dot_class: "bg-amber-500",
        name_class: "text-amber-800",
        blurb_class: "text-amber-700/80"
      }
    ]
  end
end
