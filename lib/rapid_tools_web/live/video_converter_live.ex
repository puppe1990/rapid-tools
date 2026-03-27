defmodule RapidToolsWeb.VideoConverterLive do
  use RapidToolsWeb, :live_view

  alias RapidTools.ConversionStore
  alias RapidTools.VideoConverter
  alias RapidTools.ZipArchive

  @video_accept ~w(video/mp4 video/quicktime video/webm video/x-msvideo)

  @impl true
  def mount(_params, _session, socket) do
    form =
      to_form(
        %{"target_format" => default_target_format()},
        as: :conversion
      )

    {:ok,
     socket
     |> assign(:formats, VideoConverter.supported_formats())
     |> assign(:tools, tools("video"))
     |> assign(:form, form)
     |> assign(:results, [])
     |> assign(:batch_download_path, nil)
     |> allow_upload(:video, accept: @video_accept, max_entries: 10)}
  end

  @impl true
  def handle_event("validate", %{"conversion" => conversion_params}, socket) do
    {:noreply, assign(socket, :form, to_form(conversion_params, as: :conversion))}
  end

  @impl true
  def handle_event("convert", %{"conversion" => %{"target_format" => target_format}}, socket) do
    case uploaded_entries(socket, :video) do
      {[], []} ->
        {:noreply, put_flash(socket, :error, "Selecione um video antes de converter.")}

      {_completed, [_ | _]} ->
        {:noreply, put_flash(socket, :error, "Aguarde o upload terminar antes de converter.")}

      _ ->
        {:noreply, convert_upload(socket, target_format)}
    end
  end

  defp convert_upload(socket, target_format) do
    results =
      consume_uploaded_entries(socket, :video, fn %{path: path}, entry ->
        output_dir =
          Path.join(
            System.tmp_dir!(),
            "rapid_tools_live/#{System.unique_integer([:positive])}"
          )

        File.mkdir_p!(output_dir)

        source_path = Path.join(output_dir, entry.client_name)
        File.cp!(path, source_path)

        case VideoConverter.convert(source_path, target_format, output_dir: output_dir) do
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
              |> put_flash(:info, "#{length(successful_results)} videos convertidos.")

            {:error, _reason} ->
              socket
              |> assign(:results, successful_results)
              |> assign(:batch_download_path, nil)
              |> put_flash(:error, "Os videos foram convertidos, mas o ZIP nao pode ser gerado.")
          end
        else
          put_flash(socket, :error, "O video nao pode ser convertido.")
        end

      _ ->
        put_flash(socket, :error, "O video nao pode ser convertido.")
    end
  end

  defp default_target_format, do: "mp4"

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
      <section class="min-h-screen bg-[radial-gradient(circle_at_top_left,_rgba(0,163,255,0.14),_transparent_30%),radial-gradient(circle_at_bottom_right,_rgba(255,118,35,0.16),_transparent_28%),linear-gradient(180deg,_rgba(245,247,250,1)_0%,_rgba(255,255,255,1)_52%,_rgba(242,245,249,1)_100%)]">
        <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)]">
            <aside class="rounded-[2rem] border border-white/70 bg-white/80 p-5 shadow-[0_18px_50px_rgba(15,23,42,0.08)] backdrop-blur">
              <div class="space-y-6">
                <div class="space-y-2">
                  <p class="text-sm font-semibold uppercase tracking-[0.3em] text-sky-600">
                    Rapid Tools
                  </p>
                  <div>
                    <h2 class="text-2xl font-black tracking-tight text-slate-950">Tools</h2>
                    <p class="mt-1 text-sm text-slate-600">
                      Conversores rapidos para formatos usados no mercado.
                    </p>
                  </div>
                </div>

                <nav class="space-y-3" aria-label="Tools">
                  <.link
                    :for={tool <- @tools}
                    navigate={tool.path}
                    class={[
                      "block rounded-[1.5rem] border px-4 py-4 transition duration-200",
                      tool.current &&
                        "border-sky-300 bg-sky-50 shadow-[inset_0_1px_0_rgba(255,255,255,0.9)]",
                      !tool.current &&
                        "border-slate-200 bg-white hover:border-sky-200 hover:bg-slate-50"
                    ]}
                  >
                    <p class="text-sm font-semibold text-slate-950">{tool.name}</p>
                    <p class="mt-1 text-sm text-slate-600">{tool.blurb}</p>
                  </.link>
                </nav>
              </div>
            </aside>

            <div class="space-y-6">
              <div class="space-y-4 px-2 py-2">
                <span class="inline-flex items-center rounded-full border border-sky-200 bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-sky-700">
                  Video workflow
                </span>
                <h1 class="text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
                  Video Converter
                </h1>
                <p class="max-w-3xl text-base text-slate-600 sm:text-lg">
                  Converta videos para MP4, MOV, WEBM, MKV e AVI com um fluxo simples e downloads individuais ou em lote.
                </p>
                <p class="text-sm text-slate-500">
                  Ideal para exportar assets para web, social, compatibilidade com players e arquivos mestre.
                </p>
              </div>

              <div id="video-converter-panel" class="grid gap-6 xl:grid-cols-[1.35fr_0.65fr]">
                <div class="relative rounded-[2rem] border border-white/70 bg-white p-6 shadow-[0_24px_60px_rgba(15,23,42,0.08)]">
                  <.form
                    for={@form}
                    id="video-converter-form"
                    phx-change="validate"
                    phx-submit="convert"
                    class="space-y-6"
                  >
                    <div class="pointer-events-none absolute inset-0 z-10 hidden items-center justify-center rounded-[2rem] bg-white/80 backdrop-blur-sm phx-submit-loading:flex">
                      <div class="flex items-center gap-3 rounded-full border border-sky-200 bg-white px-5 py-3 shadow-lg">
                        <span class="inline-block size-5 animate-spin rounded-full border-2 border-sky-200 border-t-sky-600" />
                        <div>
                          <p class="text-sm font-semibold text-slate-950">Convertendo video</p>
                          <p class="text-xs text-slate-500">Isso pode levar alguns segundos.</p>
                        </div>
                      </div>
                    </div>

                    <div class="rounded-[1.75rem] border border-dashed border-sky-200 bg-sky-50/60 p-5">
                      <div class="space-y-2">
                        <label for="video-upload" class="text-sm font-semibold text-slate-900">
                          Video de origem
                        </label>
                        <.live_file_input
                          upload={@uploads.video}
                          id="video-upload"
                          class="block w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700 shadow-sm transition file:mr-4 file:rounded-xl file:border-0 file:bg-slate-950 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-white hover:border-sky-300"
                        />
                        <p class="text-sm text-slate-500">
                          Entradas aceitas: MP4, MOV, WEBM, MKV e AVI.
                        </p>
                      </div>

                      <div class="mt-4 space-y-2">
                        <div
                          :for={entry <- @uploads.video.entries}
                          class="flex items-center justify-between rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700"
                        >
                          <span class="truncate pr-3 font-medium">{entry.client_name}</span>
                          <span class="text-xs uppercase tracking-[0.2em] text-slate-400">
                            pronto
                          </span>
                        </div>
                      </div>
                    </div>

                    <.input
                      field={@form[:target_format]}
                      type="select"
                      id="video-target-format"
                      label="Formato de destino"
                      options={Enum.map(@formats, &{String.upcase(&1), &1})}
                      class="w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none transition focus:border-sky-400"
                    />

                    <button
                      type="submit"
                      id="video-convert-button"
                      phx-disable-with="Convertendo video..."
                      class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-sky-700 disabled:cursor-wait disabled:opacity-90"
                    >
                      <span class="inline-block size-4 animate-spin rounded-full border-2 border-white/30 border-t-white opacity-0 phx-submit-loading:opacity-100" />
                      <span>Converter video</span>
                    </button>
                  </.form>
                </div>

                <aside class="rounded-[2rem] border border-white/70 bg-slate-950 p-6 text-white shadow-[0_24px_60px_rgba(15,23,42,0.16)]">
                  <div :if={@results != []} class="space-y-4">
                    <p class="text-sm font-semibold uppercase tracking-[0.25em] text-sky-300">
                      {length(@results)} videos convertidos
                    </p>
                    <a
                      :if={@batch_download_path}
                      href={@batch_download_path}
                      class="inline-flex w-full items-center justify-center rounded-2xl bg-sky-400 px-4 py-3 text-sm font-semibold text-slate-950 transition hover:bg-sky-300"
                    >
                      Baixar pacote ZIP
                    </a>
                    <div class="space-y-3">
                      <div
                        :for={result <- @results}
                        class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4"
                      >
                        <p class="font-semibold">{result.filename}</p>
                        <p class="mt-1 text-sm text-slate-300">
                          Saida em {String.upcase(result.target_format)}
                        </p>
                        <a
                          href={result.download_path}
                          class="mt-3 inline-flex w-full items-center justify-center rounded-2xl border border-white/10 bg-white/10 px-4 py-3 text-sm font-semibold text-white transition hover:bg-white/20"
                        >
                          Baixar arquivo convertido
                        </a>
                      </div>
                    </div>
                  </div>
                  <div :if={@results == []} class="space-y-4">
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold uppercase tracking-[0.25em] text-sky-300">
                        Formatos populares
                      </p>
                      <p class="mt-3 text-sm text-slate-300">
                        MP4 para compatibilidade ampla, MOV para ecossistema Apple, WEBM para web, MKV para alta flexibilidade e AVI para legados.
                      </p>
                    </div>
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold text-white">Saidas suportadas</p>
                      <p class="mt-2 text-sm text-slate-300">
                        {Enum.map_join(@formats, ", ", &String.upcase/1)}
                      </p>
                    </div>
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
