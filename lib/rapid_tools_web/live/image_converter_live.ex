defmodule RapidToolsWeb.ImageConverterLive do
  use RapidToolsWeb, :live_view

  alias RapidTools.ConversionStore
  alias RapidTools.ImageConverter
  alias RapidTools.ZipArchive

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:formats, ImageConverter.supported_formats())
     |> assign(:tools, tools("image"))
     |> assign(:form, to_form(%{"target_format" => "png"}, as: :conversion))
     |> assign(:results, [])
     |> assign(:batch_download_path, nil)
     |> allow_upload(:image,
       accept: ~w(.jpg .jpeg .png .webp .heic .avif),
       max_entries: 10
     )}
  end

  @impl true
  def handle_event("validate", %{"conversion" => conversion_params}, socket) do
    {:noreply, assign(socket, :form, to_form(conversion_params, as: :conversion))}
  end

  @impl true
  def handle_event("convert", %{"conversion" => %{"target_format" => target_format}}, socket) do
    case uploaded_entries(socket, :image) do
      {[], []} ->
        {:noreply, put_flash(socket, :error, "Select an image before converting.")}

      {_completed, [_ | _]} ->
        {:noreply, put_flash(socket, :error, "Wait for all uploads to finish before converting.")}

      _ ->
        {:noreply, convert_upload(socket, target_format)}
    end
  end

  defp convert_upload(socket, target_format) do
    results =
      consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
        output_dir =
          Path.join(
            System.tmp_dir!(),
            "rapid_tools_live/#{System.unique_integer([:positive])}"
          )

        File.mkdir_p!(output_dir)

        source_path = Path.join(output_dir, entry.client_name)
        File.cp!(path, source_path)

        case ImageConverter.convert(source_path, target_format, output_dir: output_dir) do
          {:ok, result} ->
            store_entry = %{
              path: result.output_path,
              filename: result.filename,
              media_type: result.media_type
            }

            {:ok, id} = ConversionStore.put(store_entry)

            {:ok,
             {:ok,
              %{
                download_path: ~p"/downloads/#{id}",
                output_path: result.output_path,
                media_type: result.media_type,
                filename: result.filename,
                target_format: result.target_format
              }}}

          {:error, reason} ->
            {:ok, {:error, reason}}
        end
      end)

    case results do
      converted when is_list(converted) ->
        successful_results = Enum.map(converted, fn {:ok, result} -> result end)

        if successful_results != [] and length(successful_results) == length(converted) do
          batch_entries =
            Enum.map(successful_results, fn result ->
              %{
                path: result.output_path,
                filename: result.filename,
                media_type: result.media_type
              }
            end)

          {:ok, batch_id} = ConversionStore.put_batch(batch_entries)

          case ZipArchive.build(batch_id, batch_entries) do
            {:ok, zip_entry} ->
              {:ok, zip_id} = ConversionStore.put(zip_entry)

              socket
              |> assign(:results, successful_results)
              |> assign(:batch_download_path, ~p"/downloads/#{zip_id}")
              |> put_flash(:info, "#{length(successful_results)} files converted.")

            {:error, _reason} ->
              socket
              |> assign(:results, successful_results)
              |> assign(:batch_download_path, nil)
              |> put_flash(
                :error,
                "Files were converted, but the ZIP package could not be created."
              )
          end
        else
          put_flash(socket, :error, "The image could not be converted.")
        end

      _ ->
        put_flash(socket, :error, "The image could not be converted.")
    end
  end

  defp tools(current) do
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
      }
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      main_class="px-0 py-8 sm:px-0 lg:px-0"
      content_class="w-full"
      show_header={false}
    >
      <section class="min-h-screen bg-[radial-gradient(circle_at_top_left,_rgba(255,118,35,0.12),_transparent_28%),linear-gradient(180deg,_rgba(245,246,248,1)_0%,_rgba(255,255,255,1)_52%,_rgba(244,245,246,1)_100%)]">
        <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)]">
            <aside class="rounded-[2rem] border border-base-300/80 bg-base-100/85 p-5 shadow-[0_18px_50px_rgba(24,24,27,0.08)] backdrop-blur">
              <div class="space-y-6">
                <div class="space-y-2">
                  <p class="text-sm font-semibold uppercase tracking-[0.3em] text-primary">
                    Rapid Tools
                  </p>
                  <div>
                    <h2 class="text-2xl font-black tracking-tight">Tools</h2>
                    <p class="mt-1 text-sm text-base-content/60">
                      Utilities available in this workspace.
                    </p>
                  </div>
                </div>

                <nav class="space-y-3" aria-label="Tools">
                  <.link
                    :for={tool <- @tools}
                    navigate={tool.path}
                    class={[
                      "block rounded-[1.5rem] border px-4 py-4 transition",
                      tool.current &&
                        "border-primary/30 bg-primary/8 shadow-[inset_0_1px_0_rgba(255,255,255,0.65)]",
                      !tool.current &&
                        "border-base-300 bg-base-100 hover:border-primary/20 hover:bg-base-200/70"
                    ]}
                  >
                    <p class="text-sm font-semibold">{tool.name}</p>
                    <p class="mt-1 text-sm text-base-content/60">{tool.blurb}</p>
                  </.link>
                </nav>
              </div>
            </aside>

            <div class="space-y-6">
              <div class="space-y-4 px-2 py-2">
                <h1 class="text-4xl font-black tracking-tight sm:text-5xl">Image Converter</h1>
                <p class="max-w-2xl text-base text-base-content/70 sm:text-lg">
                  Convert JPG, PNG, WEBP, HEIC and AVIF directly in the browser with Phoenix LiveView.
                </p>
                <p class="text-sm text-base-content/60">
                  You can select multiple images and convert them in one batch.
                </p>
              </div>

              <div id="converter-panel" class="grid gap-6 xl:grid-cols-[1.35fr_0.65fr]">
                <div class="relative rounded-[2rem] border border-base-300 bg-base-100 p-6 shadow-xl">
                  <.form
                    for={@form}
                    id="converter-form"
                    phx-change="validate"
                    phx-submit="convert"
                    class="space-y-6"
                  >
                    <div class="pointer-events-none absolute inset-0 z-10 hidden items-center justify-center rounded-[2rem] bg-base-100/80 backdrop-blur-sm phx-submit-loading:flex">
                      <div class="flex items-center gap-3 rounded-full border border-primary/20 bg-base-100 px-5 py-3 shadow-lg">
                        <span class="inline-block size-5 animate-spin rounded-full border-2 border-primary/20 border-t-primary" />
                        <div>
                          <p class="text-sm font-semibold text-base-content">Converting image</p>
                          <p class="text-xs text-base-content/60">
                            Please wait while the files are processed.
                          </p>
                        </div>
                      </div>
                    </div>

                    <div class="space-y-2">
                      <label for="image-upload" class="text-sm font-semibold">Image</label>
                      <.live_file_input
                        upload={@uploads.image}
                        id="image-upload"
                        class="file-input file-input-bordered w-full"
                      />
                      <div
                        :for={entry <- @uploads.image.entries}
                        class="rounded-box bg-base-200 px-3 py-2 text-sm"
                      >
                        {entry.client_name}
                      </div>
                    </div>

                    <.input
                      field={@form[:target_format]}
                      type="select"
                      id="target_format"
                      label="Target format"
                      options={Enum.map(@formats, &{String.upcase(&1), &1})}
                      class="select select-bordered w-full"
                    />

                    <button
                      type="submit"
                      id="image-convert-button"
                      phx-disable-with="Converting image..."
                      class="btn btn-primary w-full disabled:cursor-wait"
                    >
                      <span class="inline-block size-4 animate-spin rounded-full border-2 border-white/30 border-t-white opacity-0 phx-submit-loading:opacity-100" />
                      <span>Convert image</span>
                    </button>
                  </.form>
                </div>

                <aside class="rounded-[2rem] border border-base-300 bg-base-100 p-6 shadow-xl">
                  <div :if={@results != []} class="space-y-4">
                    <p class="text-sm font-semibold uppercase tracking-[0.25em] text-success">
                      {length(@results)} files converted
                    </p>
                    <a
                      :if={@batch_download_path}
                      href={@batch_download_path}
                      class="btn btn-accent w-full"
                    >
                      Download all as ZIP
                    </a>
                    <div class="space-y-3">
                      <div
                        :for={result <- @results}
                        class="rounded-box border border-base-300 bg-base-200/60 p-3"
                      >
                        <p class="font-semibold">{result.filename}</p>
                        <a href={result.download_path} class="btn btn-secondary mt-3 w-full">
                          Download converted file
                        </a>
                      </div>
                    </div>
                  </div>
                  <div :if={@results == []} class="space-y-3 text-sm text-base-content/70">
                    <p class="font-semibold text-base-content">Supported outputs</p>
                    <p>{Enum.map_join(@formats, ", ", &String.upcase/1)}</p>
                    <p>The converted files will appear here as soon as the upload finishes.</p>
                  </div>
                </aside>
              </div>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
