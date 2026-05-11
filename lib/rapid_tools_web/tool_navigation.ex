defmodule RapidToolsWeb.ToolNavigation do
  @moduledoc """
  Shared navigation metadata for the converter tool sidebar.
  """
  use Phoenix.VerifiedRoutes,
    endpoint: RapidToolsWeb.Endpoint,
    router: RapidToolsWeb.Router,
    statics: RapidToolsWeb.static_paths()

  use Gettext, backend: RapidToolsWeb.Gettext

  def tools(current) do
    [
      %{
        key: "image",
        name: gettext("Image Converter"),
        blurb: gettext("Batch image conversion"),
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
        name: gettext("Video Converter"),
        blurb: gettext("Convert MP4, MOV, WEBM, MKV and AVI"),
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
        key: "image-resizer",
        name: gettext("Image Resizer"),
        blurb: gettext("Resize for social, stores and thumbnails"),
        current: current == "image-resizer",
        path: ~p"/image-resizer",
        current_class: "border-cyan-300 bg-cyan-50 shadow-[inset_0_1px_0_rgba(255,255,255,0.9)]",
        idle_class: "border-slate-200 bg-white hover:border-cyan-200 hover:bg-cyan-50/40",
        dot_class: "bg-cyan-500",
        name_class: "text-cyan-800",
        blurb_class: "text-cyan-700/80"
      },
      %{
        key: "video-compressor",
        name: gettext("Video Compressor"),
        blurb: gettext("Reduce file size for sharing and upload"),
        current: current == "video-compressor",
        path: ~p"/video-compressor",
        current_class: "border-rose-300 bg-rose-50 shadow-[inset_0_1px_0_rgba(255,255,255,0.9)]",
        idle_class: "border-slate-200 bg-white hover:border-rose-200 hover:bg-rose-50/40",
        dot_class: "bg-rose-500",
        name_class: "text-rose-800",
        blurb_class: "text-rose-700/80"
      },
      %{
        key: "extract-audio",
        name: gettext("Extract Audio"),
        blurb: gettext("Pull MP3, WAV, OGG, AAC and FLAC from video"),
        current: current == "extract-audio",
        path: ~p"/extract-audio",
        current_class:
          "border-fuchsia-300 bg-fuchsia-50 shadow-[inset_0_1px_0_rgba(255,255,255,0.9)]",
        idle_class: "border-slate-200 bg-white hover:border-fuchsia-200 hover:bg-fuchsia-50/40",
        dot_class: "bg-fuchsia-500",
        name_class: "text-fuchsia-800",
        blurb_class: "text-fuchsia-700/80"
      },
      %{
        key: "audio",
        name: gettext("Audio Converter"),
        blurb: gettext("Convert MP3, WAV, OGG, AAC and FLAC"),
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
        key: "document-converter",
        name: gettext("Document Converter"),
        blurb: gettext("Convert PDFs, docs and text files"),
        current: current == "document-converter",
        path: ~p"/document-converter",
        current_class:
          "border-violet-300 bg-violet-50 shadow-[inset_0_1px_0_rgba(255,255,255,0.9)]",
        idle_class: "border-slate-200 bg-white hover:border-violet-200 hover:bg-violet-50/40",
        dot_class: "bg-violet-500",
        name_class: "text-violet-800",
        blurb_class: "text-violet-700/80"
      },
      %{
        key: "photos-to-pdf",
        name: gettext("Photos to PDF"),
        blurb: gettext("Reorder images and export a single PDF"),
        current: current == "photos-to-pdf",
        path: ~p"/photos-to-pdf",
        current_class: "border-sky-300 bg-sky-50 shadow-[inset_0_1px_0_rgba(255,255,255,0.9)]",
        idle_class: "border-slate-200 bg-white hover:border-sky-200 hover:bg-sky-50/40",
        dot_class: "bg-sky-500",
        name_class: "text-sky-800",
        blurb_class: "text-sky-700/80"
      },
      %{
        key: "together-audios",
        name: gettext("Together Audios"),
        blurb: gettext("Join multiple audio files into one track"),
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
