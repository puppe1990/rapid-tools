defmodule RapidToolsWeb.VideoConverterLive do
  use RapidToolsWeb, :live_view

  alias RapidTools.ConversionStore
  alias RapidTools.VideoConverter
  alias RapidTools.ZipArchive
  alias RapidToolsWeb.ToolNavigation

  @video_accept ~w(.mp4 .mov .webm .mkv .avi video/mp4 video/quicktime video/webm video/x-msvideo video/x-matroska application/octet-stream audio/webm)
  @max_video_upload_size 150_000_000

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
     |> assign(:tools, ToolNavigation.tools("video"))
     |> assign(:form, form)
     |> assign(:results, [])
     |> assign(:batch_download_path, nil)
     |> allow_upload(:video,
       accept: @video_accept,
       max_entries: 10,
       max_file_size: @max_video_upload_size,
       auto_upload: true
     )}
  end

  @impl true
  def handle_event("validate", %{"conversion" => conversion_params}, socket) do
    {:noreply, assign(socket, :form, to_form(conversion_params, as: :conversion))}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :video, ref)}
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

    case successful_batch_results(results) do
      {:ok, successful_results} ->
        build_batch_response(
          socket,
          successful_results,
          "#{length(successful_results)} videos convertidos.",
          "Os videos foram convertidos, mas o ZIP nao pode ser gerado."
        )

      :error ->
        put_flash(socket, :error, conversion_error_message(results))
    end
  end

  defp successful_batch_results(converted) when is_list(converted) do
    with [_ | _] <- converted,
         true <- Enum.all?(converted, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(converted, fn {:ok, result} -> result end)}
    else
      _ -> :error
    end
  end

  defp successful_batch_results(_), do: :error

  defp conversion_error_message([{:error, :no_video_stream}]),
    do:
      "Este arquivo nao possui uma trilha de video. Envie um video valido em MP4, MOV, WEBM, MKV ou AVI."

  defp conversion_error_message([{:error, :invalid_media_file}]),
    do:
      "Este arquivo parece corrompido ou incompleto. Gere o video novamente e tente outro upload."

  defp conversion_error_message(_results), do: "O video nao pode ser convertido."

  defp build_batch_response(socket, successful_results, success_message, zip_error_message) do
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
        |> put_flash(:info, success_message)

      {:error, _reason} ->
        socket
        |> assign(:results, successful_results)
        |> assign(:batch_download_path, nil)
        |> put_flash(:error, zip_error_message)
    end
  end

  defp default_target_format, do: "mp4"

  defp completed_upload_count(entries) do
    Enum.count(entries, &(&1.progress == 100))
  end

  defp upload_in_progress?(entries) do
    Enum.any?(entries, &(&1.progress < 100))
  end

  defp upload_status_message(entries) do
    cond do
      entries == [] ->
        "Selecione um ou mais videos para habilitar a conversao."

      upload_in_progress?(entries) ->
        "Enviando videos para o servidor. Aguarde todos chegarem a 100%."

      true ->
        "Uploads concluidos. Agora voce pode converter em lote."
    end
  end

  defp upload_summary(entries) do
    total = length(entries)
    completed = completed_upload_count(entries)

    cond do
      total == 0 ->
        "Nenhum video selecionado ainda."

      upload_in_progress?(entries) ->
        "#{total} videos na fila. #{completed}/#{total} concluidos ate agora, o restante ainda esta enviando."

      true ->
        "#{total} videos selecionados. Todos aparecem nesta caixa com scroll."
    end
  end

  defp upload_error_message(:not_accepted),
    do: "Formato nao aceito. Envie MP4, MOV, WEBM, MKV ou AVI."

  defp upload_error_message(:too_large), do: "O arquivo excede o limite permitido para upload."

  defp upload_error_message(:too_many_files),
    do: "Voce selecionou mais arquivos do que o permitido."

  defp upload_error_message(:external_client_failure),
    do: "O navegador nao conseguiu enviar este arquivo. Tente novamente."

  defp upload_error_message(_error), do: "Nao foi possivel enviar este arquivo."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      main_class="px-0 pb-8 pt-0 sm:px-0 lg:px-0"
      content_class="w-full"
      show_header={false}
    >
      <section class="min-h-screen bg-[radial-gradient(circle_at_top_left,_rgba(99,102,241,0.18),_transparent_30%),radial-gradient(circle_at_bottom_right,_rgba(56,189,248,0.14),_transparent_28%),linear-gradient(180deg,_rgba(241,244,252,1)_0%,_rgba(255,255,255,1)_52%,_rgba(238,242,252,1)_100%)]">
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
                      tool.current && tool.current_class,
                      !tool.current && tool.idle_class
                    ]}
                  >
                    <div class="flex items-center gap-3">
                      <span class={["inline-block size-2.5 rounded-full", tool.dot_class]} />
                      <p class={["text-sm font-semibold", tool.name_class]}>{tool.name}</p>
                    </div>
                    <p class={["mt-1 text-sm", tool.blurb_class]}>{tool.blurb}</p>
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
                          Entradas aceitas: MP4, MOV, WEBM, MKV e AVI. Ate 150 MB por video.
                        </p>
                      </div>

                      <div
                        id="video-upload-list"
                        class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                      >
                        <div class="sticky top-0 z-10 rounded-2xl border border-sky-100 bg-sky-50/95 px-4 py-3 text-sm font-medium text-sky-900 backdrop-blur">
                          {upload_summary(@uploads.video.entries)}
                        </div>
                        <div
                          :for={entry <- @uploads.video.entries}
                          class="flex items-center gap-3 rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700"
                        >
                          <div class="min-w-0 flex-1 pr-4">
                            <p class="truncate font-medium">{entry.client_name}</p>
                            <div class="mt-2 h-2 rounded-full bg-slate-100">
                              <div
                                class="h-2 rounded-full bg-sky-400 transition-all"
                                style={"width: #{entry.progress}%"}
                              />
                            </div>
                            <p
                              :for={error <- upload_errors(@uploads.video, entry)}
                              class="mt-2 text-xs font-medium text-rose-600"
                            >
                              {upload_error_message(error)}
                            </p>
                          </div>
                          <span class="text-xs uppercase tracking-[0.2em] text-slate-400">
                            <%= if entry.progress == 100 do %>
                              pronto
                            <% else %>
                              {entry.progress}%
                            <% end %>
                          </span>
                          <button
                            type="button"
                            phx-click="cancel-upload"
                            phx-value-ref={entry.ref}
                            aria-label={"Remover #{entry.client_name}"}
                            class="inline-flex size-8 shrink-0 items-center justify-center rounded-full border border-slate-200 text-sm font-bold text-slate-500 transition hover:border-red-200 hover:bg-red-50 hover:text-red-600"
                          >
                            X
                          </button>
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
                      disabled={
                        @uploads.video.entries == [] || upload_in_progress?(@uploads.video.entries)
                      }
                      class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-sky-700 disabled:cursor-wait disabled:opacity-90"
                    >
                      <span class="inline-block size-4 animate-spin rounded-full border-2 border-white/30 border-t-white opacity-0 phx-submit-loading:opacity-100" />
                      <span>Converter video</span>
                    </button>

                    <p id="video-converter-status" class="text-sm text-slate-500">
                      {upload_status_message(@uploads.video.entries)}
                    </p>
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
