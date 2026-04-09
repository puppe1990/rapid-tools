defmodule RapidToolsWeb.ExtractAudioLive do
  use RapidToolsWeb, :live_view

  alias Phoenix.LiveView.UploadConfig
  alias RapidTools.AudioExtractor
  alias RapidTools.ConversionStore
  alias RapidTools.ZipArchive
  alias RapidToolsWeb.ToolNavigation

  @video_accept ~w(.mp4 .mov .webm .mkv .avi .ts video/mp4 video/quicktime video/webm video/x-msvideo video/x-matroska video/mp2t video/mpeg application/octet-stream audio/webm)
  @max_video_upload_size 1_073_741_824

  @impl true
  def mount(_params, _session, socket) do
    form =
      to_form(
        %{"target_format" => default_target_format()},
        as: :conversion
      )

    {:ok,
     socket
     |> assign(:formats, AudioExtractor.supported_formats())
     |> assign(:tools, ToolNavigation.tools("extract-audio"))
     |> assign(:form, form)
     |> assign(:results, [])
     |> assign(:batch_download_path, nil)
     |> assign(:upload_issue, nil)
     |> assign(:currently_extracting, nil)
     |> assign(:processing_queue, [])
     |> assign(:processing_total, 0)
     |> assign(:current_locale, socket.assigns[:current_locale] || "en")
     |> assign(:my_path, "/extract-audio")
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
            {:noreply,
             put_flash(socket, :error, gettext("Selecione um video antes de extrair o audio."))}

          {_completed, [_ | _]} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Aguarde o upload terminar antes de extrair o audio.")
             )}

          _ ->
            {:noreply, start_extraction(socket, target_format)}
        end
    end
  end

  @impl true
  def handle_info({:begin_audio_extraction, staged_entries, target_format, results}, socket) do
    case staged_entries do
      [] ->
        {:noreply, finish_extraction(socket, Enum.reverse(results))}

      [entry | rest] ->
        send(self(), {:run_audio_extraction, entry, rest, target_format, results})

        {:noreply,
         socket
         |> assign(:currently_extracting, entry.client_name)
         |> assign(:processing_queue, Enum.map([entry | rest], & &1.client_name))}
    end
  end

  @impl true
  def handle_info({:run_audio_extraction, entry, rest, target_format, results}, socket) do
    result = extract_staged_entry(entry, target_format)
    send(self(), {:begin_audio_extraction, rest, target_format, [result | results]})
    {:noreply, socket}
  end

  defp start_extraction(socket, target_format) do
    case stage_uploaded_entries(socket) do
      {:ok, []} ->
        put_flash(socket, :error, gettext("Selecione um video antes de extrair o audio."))

      {:ok, staged_entries} ->
        send(self(), {:begin_audio_extraction, staged_entries, target_format, []})

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

  defp extract_staged_entry(entry, target_format) do
    case AudioExtractor.extract(entry.source_path, target_format, output_dir: entry.output_dir) do
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

  defp finish_extraction(socket, results) do
    socket =
      socket
      |> assign(:currently_extracting, nil)
      |> assign(:processing_queue, [])
      |> assign(:processing_total, 0)

    case successful_batch_results(results) do
      {:ok, successful_results} ->
        build_batch_response(
          socket,
          successful_results,
          "#{length(successful_results)} audios extraidos.",
          gettext("Os audios foram extraidos, mas o ZIP nao pode ser gerado.")
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
    gettext("O upload deste video foi perdido antes da extracao. Envie o arquivo novamente.")
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

  defp conversion_error_message([{:error, :no_audio_stream}]),
    do:
      gettext("Este video nao possui uma trilha de audio. Envie um arquivo com som para extrair.")

  defp conversion_error_message([{:error, :invalid_media_file}]),
    do:
      gettext(
        "Este arquivo parece corrompido ou incompleto. Gere o video novamente e tente outro upload."
      )

  defp conversion_error_message(_results), do: gettext("O audio nao pode ser extraido.")

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

  defp default_target_format, do: "mp3"

  defp completed_upload_count(entries) do
    Enum.count(entries, &(&1.progress == 100))
  end

  defp upload_in_progress?(entries) do
    Enum.any?(entries, &(&1.progress < 100))
  end

  defp upload_status_message(entries, currently_extracting) do
    cond do
      processing?(currently_extracting) ->
        gettext("Extracao em andamento. Acompanhe qual video esta sendo processado agora.")

      entries == [] ->
        gettext("Selecione um ou mais videos para habilitar a extracao.")

      upload_in_progress?(entries) ->
        gettext("Enviando videos para o servidor. Aguarde todos chegarem a 100%.")

      true ->
        gettext("Uploads concluidos. Agora voce pode extrair o audio em lote.")
    end
  end

  defp upload_summary(entries, currently_extracting) do
    total = length(entries)
    completed = completed_upload_count(entries)

    cond do
      processing?(currently_extracting) ->
        gettext(
          "Fila enviada para extracao. O video atual aparece com loader e o restante fica na sequencia."
        )

      total == 0 ->
        gettext("Nenhum video selecionado ainda.")

      upload_in_progress?(entries) ->
        "#{total} videos na fila. #{completed}/#{total} concluidos ate agora, o restante ainda esta enviando."

      true ->
        "#{total} videos selecionados. Todos aparecem nesta caixa com scroll."
    end
  end

  defp processing?(currently_extracting), do: currently_extracting != nil

  defp processing_position(assigns) do
    queue_count = length(assigns.processing_queue)

    if assigns.processing_total > 0 and queue_count > 0 do
      assigns.processing_total - queue_count + 1
    else
      0
    end
  end

  defp upload_error_message(:not_accepted),
    do: gettext("Formato nao aceito. Envie MP4, MOV, WEBM, MKV, AVI ou TS.")

  defp upload_error_message(:too_large),
    do: gettext("O arquivo excede o limite permitido para upload.")

  defp upload_error_message(:too_many_files),
    do: gettext("Voce selecionou mais arquivos do que o permitido.")

  defp upload_error_message(:external_client_failure),
    do: gettext("O navegador nao conseguiu enviar este arquivo. Tente novamente.")

  defp upload_error_message(_error), do: gettext("Nao foi possivel enviar este arquivo.")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      main_class="px-0 pb-8 pt-0 sm:px-0 lg:px-0"
      content_class="w-full"
      show_header={false}
    >
      <section class="min-h-screen bg-[radial-gradient(circle_at_top_left,_rgba(168,85,247,0.16),_transparent_28%),radial-gradient(circle_at_bottom_right,_rgba(236,72,153,0.14),_transparent_28%),linear-gradient(180deg,_rgba(249,244,252,1)_0%,_rgba(255,255,255,1)_52%,_rgba(250,243,248,1)_100%)]">
        <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)]">
            <.tool_sidebar
              tools={@tools}
              current_locale={@current_locale}
              redirect_to={@my_path}
              theme={%{sidebar_border_class: "border-white/70", accent_class: "text-fuchsia-600"}}
            />

            <div class="space-y-6">
              <div class="space-y-4 px-2 py-2">
                <span class="inline-flex items-center rounded-full border border-fuchsia-200 bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-fuchsia-700">
                  Audio extraction
                </span>
                <h1 class="text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
                  Extract Audio
                </h1>
                <p class="max-w-3xl text-base text-slate-600 sm:text-lg">
                  {gettext(
                    "Extraia o audio de videos em MP3, WAV, OGG, AAC e FLAC com downloads individuais ou em lote."
                  )}
                </p>
                <p class="text-sm text-slate-500">
                  {gettext(
                    "Ideal para reaproveitar entrevistas, podcasts em video, aulas, lives e trilhas capturadas em camera."
                  )}
                </p>
              </div>

              <div id="extract-audio-panel" class="grid gap-6 xl:grid-cols-[1.35fr_0.65fr]">
                <div class="relative rounded-[2rem] border border-white/70 bg-white p-6 shadow-[0_24px_60px_rgba(15,23,42,0.08)]">
                  <.form
                    for={@form}
                    id="extract-audio-form"
                    phx-change="validate"
                    phx-submit="convert"
                    class="space-y-6"
                  >
                    <div class="pointer-events-none absolute inset-0 z-10 hidden items-center justify-center rounded-[2rem] bg-white/80 backdrop-blur-sm phx-submit-loading:flex">
                      <div class="flex items-center gap-3 rounded-full border border-fuchsia-200 bg-white px-5 py-3 shadow-lg">
                        <span class="inline-block size-5 animate-spin rounded-full border-2 border-fuchsia-200 border-t-fuchsia-600" />
                        <div>
                          <p class="text-sm font-semibold text-slate-950">
                            {gettext("Extraindo audio")}
                          </p>
                          <p class="text-xs text-slate-500">
                            {gettext("Isso pode levar alguns segundos.")}
                          </p>
                        </div>
                      </div>
                    </div>

                    <div class="space-y-3">
                      <div>
                        <p class="text-sm font-semibold uppercase tracking-[0.25em] text-fuchsia-500">
                          {gettext("Upload de videos")}
                        </p>
                        <h2 class="mt-2 text-2xl font-black tracking-tight text-slate-950">
                          {gettext("Selecione um ou mais videos para separar o som")}
                        </h2>
                        <p class="mt-2 max-w-2xl text-sm leading-6 text-slate-600">
                          {gettext(
                            "O Rapid Tools mantem os uploads em fila, extrai o audio no formato escolhido e prepara downloads individuais e um ZIP final."
                          )}
                        </p>
                      </div>

                      <label for="extract-audio-upload" class="text-sm font-semibold text-slate-900">
                        {gettext("Escolha os videos")}
                      </label>

                      <.live_file_input
                        upload={@uploads.video}
                        id="extract-audio-upload"
                        class="block w-full rounded-[1.5rem] border border-dashed border-fuchsia-200 bg-fuchsia-50/50 px-4 py-6 text-sm text-slate-600 file:mr-4 file:rounded-full file:border-0 file:bg-fuchsia-600 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-white hover:border-fuchsia-300"
                      />

                      <p class="text-sm text-slate-500">
                        {gettext(
                          "Entradas aceitas: MP4, MOV, WEBM, MKV, AVI e TS. Ate 1 GB por video."
                        )}
                      </p>
                    </div>

                    <div
                      :if={processing?(@currently_extracting)}
                      id="extract-audio-currently-processing"
                      class="rounded-[1.5rem] border border-fuchsia-200 bg-fuchsia-50 px-4 py-4"
                    >
                      <div class="flex items-start gap-3">
                        <span class="mt-1 inline-block size-3 rounded-full bg-fuchsia-500 animate-pulse" />
                        <div class="space-y-1">
                          <p class="text-sm font-semibold text-fuchsia-900">
                            {gettext("Extraindo agora")}
                          </p>
                          <p class="text-sm text-fuchsia-800">{@currently_extracting}</p>
                          <p class="text-xs uppercase tracking-[0.25em] text-fuchsia-600">
                            {processing_position(assigns)} de {@processing_total} videos
                          </p>
                        </div>
                      </div>
                    </div>

                    <div
                      id="extract-audio-upload-list"
                      class="rounded-[1.5rem] border border-slate-200 bg-slate-50/80 p-4"
                    >
                      <div class="flex items-center justify-between gap-3">
                        <p class="text-sm font-semibold text-slate-900">
                          {gettext("Fila de upload")}
                        </p>
                        <p class="text-xs text-slate-500">
                          {upload_summary(@uploads.video.entries, @currently_extracting)}
                        </p>
                      </div>

                      <div class="mt-4 max-h-72 space-y-3 overflow-y-auto pr-1">
                        <div
                          :for={entry <- @uploads.video.entries}
                          class="rounded-[1.25rem] border border-white bg-white p-4 shadow-sm"
                        >
                          <div class="flex items-start justify-between gap-3">
                            <div class="min-w-0">
                              <p class="truncate text-sm font-semibold text-slate-900">
                                {entry.client_name}
                              </p>
                              <p class="mt-1 text-xs text-slate-500">
                                {if entry.progress == 100,
                                  do: gettext("pronto"),
                                  else: "#{entry.progress}% enviado"}
                              </p>
                            </div>

                            <button
                              type="button"
                              phx-click="cancel-upload"
                              phx-value-ref={entry.ref}
                              class="rounded-full border border-slate-200 px-3 py-1 text-xs font-semibold text-slate-600 transition hover:border-fuchsia-200 hover:text-fuchsia-700"
                              aria-label={"Remover #{entry.client_name}"}
                            >
                              {gettext("Remover")}
                            </button>
                          </div>

                          <div class="mt-3 h-2 overflow-hidden rounded-full bg-slate-200">
                            <div
                              class="h-full rounded-full bg-fuchsia-500 transition-all"
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

                        <div
                          :if={@uploads.video.entries == []}
                          class="rounded-[1.25rem] border border-dashed border-slate-200 bg-white/80 px-4 py-6 text-sm text-slate-500"
                        >
                          {gettext("Nenhum video selecionado ainda.")}
                        </div>
                      </div>
                    </div>

                    <div class="grid gap-4 md:grid-cols-[minmax(0,1fr)_auto] md:items-end">
                      <div>
                        <.input
                          field={@form[:target_format]}
                          type="select"
                          id="extract-audio-target-format"
                          label={gettext("Formato de saida")}
                          options={Enum.map(@formats, &{String.upcase(&1), &1})}
                          class="rounded-2xl border-slate-200"
                        />
                      </div>

                      <button
                        id="extract-audio-button"
                        type="submit"
                        phx-disable-with="Extraindo audio..."
                        disabled={
                          @uploads.video.entries == [] || upload_in_progress?(@uploads.video.entries) ||
                            processing?(@currently_extracting)
                        }
                        class="inline-flex items-center justify-center rounded-full bg-fuchsia-600 px-6 py-3 text-sm font-semibold text-white shadow-lg shadow-fuchsia-600/20 transition hover:bg-fuchsia-500 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:shadow-none"
                      >
                        <span>{gettext("Extrair audio")}</span>
                      </button>
                    </div>

                    <p id="extract-audio-status" class="text-sm text-slate-500">
                      {upload_status_message(@uploads.video.entries, @currently_extracting)}
                    </p>

                    <p :if={@upload_issue} class="text-sm font-medium text-rose-600">
                      {@upload_issue}
                    </p>
                  </.form>
                </div>

                <aside class="space-y-4 rounded-[2rem] border border-white/70 bg-white/90 p-6 shadow-[0_24px_60px_rgba(15,23,42,0.08)]">
                  <div>
                    <p class="text-sm font-semibold uppercase tracking-[0.25em] text-fuchsia-500">
                      {gettext("Resultados")}
                    </p>
                    <h2 class="mt-2 text-2xl font-black tracking-tight text-slate-950">
                      {gettext("Audios prontos para download")}
                    </h2>
                    <p class="mt-2 text-sm leading-6 text-slate-600">
                      {gettext(
                        "Cada arquivo extraido aparece aqui com link individual. Quando houver mais de um resultado, o lote tambem fica disponivel."
                      )}
                    </p>
                  </div>

                  <div class="rounded-[1.5rem] border border-slate-200 bg-slate-50/80 p-4">
                    <p class="text-sm font-semibold text-slate-900">
                      {length(@results)} audios extraidos
                    </p>

                    <div class="mt-4 space-y-3">
                      <div
                        :for={result <- @results}
                        class="rounded-[1.25rem] border border-white bg-white p-4 shadow-sm"
                      >
                        <p class="truncate text-sm font-semibold text-slate-900">{result.filename}</p>
                        <p class="mt-1 text-xs uppercase tracking-[0.2em] text-slate-500">
                          {String.upcase(result.target_format)}
                        </p>
                        <.link
                          navigate={result.download_path}
                          class="mt-3 inline-flex text-sm font-semibold text-fuchsia-700 hover:text-fuchsia-600"
                        >
                          {gettext("Baixar arquivo")}
                        </.link>
                      </div>

                      <div
                        :if={@results == []}
                        class="rounded-[1.25rem] border border-dashed border-slate-200 bg-white/80 px-4 py-6 text-sm text-slate-500"
                      >
                        {gettext(
                          "Os audios extraidos vao aparecer aqui assim que o processamento terminar."
                        )}
                      </div>
                    </div>
                  </div>

                  <div class="rounded-[1.5rem] border border-fuchsia-100 bg-fuchsia-50/60 p-4">
                    <p class="text-sm font-semibold text-fuchsia-900">
                      {gettext("Download em lote")}
                    </p>
                    <p class="mt-2 text-sm leading-6 text-fuchsia-900/80">
                      {gettext(
                        "Gere um ZIP com todos os audios extraidos para baixar o pacote inteiro de uma vez."
                      )}
                    </p>

                    <.link
                      :if={@batch_download_path}
                      navigate={@batch_download_path}
                      class="mt-4 inline-flex rounded-full bg-fuchsia-600 px-5 py-2 text-sm font-semibold text-white transition hover:bg-fuchsia-500"
                    >
                      {gettext("Baixar ZIP")}
                    </.link>
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
