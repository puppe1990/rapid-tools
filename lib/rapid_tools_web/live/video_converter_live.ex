defmodule RapidToolsWeb.VideoConverterLive do
  use RapidToolsWeb, :live_view

  alias Phoenix.LiveView.UploadConfig
  alias RapidTools.ConversionStore
  alias RapidTools.VideoConverter
  alias RapidTools.ZipArchive
  alias RapidToolsWeb.ToolNavigation

  @video_accept ~w(.mp4 .mov .webm .mkv .avi .ts video/mp4 video/quicktime video/webm video/x-msvideo video/x-matroska video/mp2t video/mpeg application/octet-stream audio/webm)
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
     |> assign(:upload_issue, nil)
     |> assign(:currently_converting, nil)
     |> assign(:processing_queue, [])
     |> assign(:processing_total, 0)
     |> allow_upload(:video,
       accept: @video_accept,
       max_entries: 10,
       max_file_size: @max_video_upload_size,
       auto_upload: true
     )}
  end

  @impl true
  def handle_event("validate", %{"conversion" => conversion_params}, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(conversion_params, as: :conversion))
     |> maybe_clear_upload_issue()}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, socket |> cancel_upload(:video, ref) |> maybe_clear_upload_issue()}
  end

  @impl true
  def handle_event("convert", %{"conversion" => %{"target_format" => target_format}}, socket) do
    case reconcile_video_uploads(socket) do
      {:error, socket} ->
        {:noreply, socket}

      {:ok, socket} ->
        case uploaded_entries(socket, :video) do
          {[], []} ->
            {:noreply, put_flash(socket, :error, "Selecione um video antes de converter.")}

          {_completed, [_ | _]} ->
            {:noreply, put_flash(socket, :error, "Aguarde o upload terminar antes de converter.")}

          _ ->
            {:noreply, start_conversion(socket, target_format)}
        end
    end
  end

  @impl true
  def handle_info({:begin_video_conversion, staged_entries, target_format, results}, socket) do
    case staged_entries do
      [] ->
        {:noreply, finish_conversion(socket, Enum.reverse(results))}

      [entry | rest] ->
        send(self(), {:run_video_conversion, entry, rest, target_format, results})

        {:noreply,
         socket
         |> assign(:currently_converting, entry.client_name)
         |> assign(:processing_queue, Enum.map([entry | rest], & &1.client_name))}
    end
  end

  @impl true
  def handle_info({:run_video_conversion, entry, rest, target_format, results}, socket) do
    result = convert_staged_entry(entry, target_format)
    send(self(), {:begin_video_conversion, rest, target_format, [result | results]})
    {:noreply, socket}
  end

  defp start_conversion(socket, target_format) do
    case stage_uploaded_entries(socket) do
      {:ok, []} ->
        put_flash(socket, :error, "Selecione um video antes de converter.")

      {:ok, staged_entries} ->
        send(self(), {:begin_video_conversion, staged_entries, target_format, []})

        socket
        |> assign(:results, [])
        |> assign(:batch_download_path, nil)
        |> assign(:upload_issue, nil)
        |> assign(:processing_total, length(staged_entries))

      {:error, socket} ->
        socket
    end
  end

  defp stage_uploaded_entries(socket) do
    staged_entries =
      consume_uploaded_entries(socket, :video, fn %{path: path}, entry ->
        output_dir =
          Path.join(
            System.tmp_dir!(),
            "rapid_tools_live/#{System.unique_integer([:positive])}"
          )

        File.mkdir_p!(output_dir)

        source_path = Path.join(output_dir, entry.client_name)
        File.cp!(path, source_path)

        {:ok,
         %{
           source_path: source_path,
           client_name: entry.client_name,
           output_dir: output_dir
         }}
      end)

    {:ok, staged_entries}
  catch
    :exit, _reason ->
      {:error,
       socket
       |> assign(:upload_issue, lost_upload_message())
       |> put_flash(:error, lost_upload_message())}
  end

  defp convert_staged_entry(entry, target_format) do
    case VideoConverter.convert(entry.source_path, target_format, output_dir: entry.output_dir) do
      {:ok, result} ->
        store_entry = %{
          path: result.output_path,
          filename: result.filename,
          media_type: result.media_type
        }

        {:ok, id} = ConversionStore.put(store_entry)

        {:ok,
         %{
           download_path: ~p"/downloads/#{id}",
           output_path: result.output_path,
           media_type: result.media_type,
           filename: result.filename,
           target_format: result.target_format
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp finish_conversion(socket, results) do
    socket =
      socket
      |> assign(:currently_converting, nil)
      |> assign(:processing_queue, [])
      |> assign(:processing_total, 0)

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

  defp reconcile_video_uploads(socket) do
    stale_refs = stale_video_upload_refs(socket)

    if stale_refs == [] do
      {:ok, socket}
    else
      {:error,
       socket
       |> assign(:upload_issue, lost_upload_message())
       |> put_flash(:error, lost_upload_message())}
    end
  end

  defp stale_video_upload_refs(socket) do
    conf = socket.assigns.uploads.video

    for entry <- conf.entries,
        pid = UploadConfig.entry_pid(conf, entry),
        is_pid(pid),
        not Process.alive?(pid),
        do: entry.ref
  end

  defp maybe_clear_upload_issue(socket) do
    if socket.assigns.uploads.video.entries == [] do
      assign(socket, :upload_issue, nil)
    else
      socket
    end
  end

  defp lost_upload_message do
    "O upload deste video foi perdido antes da conversao. Envie o arquivo novamente."
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
      "Este arquivo nao possui uma trilha de video. Envie um video valido em MP4, MOV, WEBM, MKV, AVI ou TS."

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

  defp upload_status_message(entries, currently_converting) do
    cond do
      processing?(currently_converting) ->
        "Conversao em andamento. Acompanhe qual arquivo esta sendo processado agora."

      entries == [] ->
        "Selecione um ou mais videos para habilitar a conversao."

      upload_in_progress?(entries) ->
        "Enviando videos para o servidor. Aguarde todos chegarem a 100%."

      true ->
        "Uploads concluidos. Agora voce pode converter em lote."
    end
  end

  defp upload_summary(entries, currently_converting) do
    total = length(entries)
    completed = completed_upload_count(entries)

    cond do
      processing?(currently_converting) ->
        "Fila enviada para conversao. O video atual aparece com loader e o restante fica na sequencia."

      total == 0 ->
        "Nenhum video selecionado ainda."

      upload_in_progress?(entries) ->
        "#{total} videos na fila. #{completed}/#{total} concluidos ate agora, o restante ainda esta enviando."

      true ->
        "#{total} videos selecionados. Todos aparecem nesta caixa com scroll."
    end
  end

  defp processing?(currently_converting), do: currently_converting != nil

  defp processing_position(assigns) do
    queue_count = length(assigns.processing_queue)

    if assigns.processing_total > 0 and queue_count > 0 do
      assigns.processing_total - queue_count + 1
    else
      0
    end
  end

  defp upload_error_message(:not_accepted),
    do: "Formato nao aceito. Envie MP4, MOV, WEBM, MKV, AVI ou TS."

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
                  Converta videos para MP4, MOV, WEBM, MKV, AVI e TS com um fluxo simples e downloads individuais ou em lote.
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
                          <p class="text-sm font-semibold text-slate-950">
                            <%= if @currently_converting do %>
                              Convertendo: {@currently_converting}
                            <% else %>
                              Convertendo video
                            <% end %>
                          </p>
                          <p class="text-xs text-slate-500">
                            <%= if @currently_converting do %>
                              Aguarde a fila avancar para o proximo arquivo.
                            <% else %>
                              Isso pode levar alguns segundos.
                            <% end %>
                          </p>
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
                          Entradas aceitas: MP4, MOV, WEBM, MKV, AVI e TS. Ate 150 MB por video.
                        </p>
                        <p
                          :if={@upload_issue}
                          class="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm font-medium text-amber-900"
                        >
                          {@upload_issue}
                        </p>
                      </div>

                      <div
                        :if={@currently_converting}
                        id="video-currently-converting"
                        class="mt-4 rounded-[1.5rem] border border-sky-200 bg-sky-100/80 p-4 text-sky-950 shadow-[inset_0_1px_0_rgba(255,255,255,0.7)]"
                      >
                        <div class="flex items-start gap-3">
                          <span class="mt-1 inline-block size-4 animate-spin rounded-full border-2 border-sky-300 border-t-sky-700" />
                          <div class="min-w-0 flex-1">
                            <p class="text-xs font-semibold uppercase tracking-[0.28em] text-sky-700">
                              Convertendo agora
                            </p>
                            <p class="mt-2 truncate text-base font-semibold text-slate-950">
                              {@currently_converting}
                            </p>
                            <p class="mt-2 text-sm text-sky-800">
                              {processing_position(assigns)} de {@processing_total} videos
                            </p>
                          </div>
                        </div>
                      </div>

                      <div
                        id="video-upload-list"
                        class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                      >
                        <div class="sticky top-0 z-10 rounded-2xl border border-sky-100 bg-sky-50/95 px-4 py-3 text-sm font-medium text-sky-900 backdrop-blur">
                          {upload_summary(@uploads.video.entries, @currently_converting)}
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
                        @uploads.video.entries == [] || upload_in_progress?(@uploads.video.entries) ||
                          processing?(@currently_converting)
                      }
                      class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-sky-700 disabled:cursor-wait disabled:opacity-90"
                    >
                      <span class="inline-block size-4 animate-spin rounded-full border-2 border-white/30 border-t-white opacity-0 phx-submit-loading:opacity-100" />
                      <span>Converter video</span>
                    </button>

                    <p id="video-converter-status" class="text-sm text-slate-500">
                      {upload_status_message(@uploads.video.entries, @currently_converting)}
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
