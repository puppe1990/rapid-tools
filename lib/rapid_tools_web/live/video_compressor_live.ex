defmodule RapidToolsWeb.VideoCompressorLive do
  use RapidToolsWeb, :live_view

  alias Phoenix.LiveView.UploadConfig
  alias RapidTools.ConversionStore
  alias RapidTools.VideoCompressor
  alias RapidTools.ZipArchive
  alias RapidToolsWeb.ToolNavigation

  @video_accept ~w(.mp4 .mov .webm .mkv .avi video/mp4 video/quicktime video/webm video/x-msvideo video/x-matroska application/octet-stream audio/webm)
  @max_video_upload_size 150_000_000

  @impl true
  def mount(_params, session, socket) do
    locale =
      Locale.set_gettext_locale(
        session["locale"] || socket.assigns[:current_locale] || Locale.default_locale()
      )

    {:ok,
     socket
     |> assign(:current_locale, locale)
     |> assign(:tools, ToolNavigation.tools("video-compressor"))
     |> assign(:results, [])
     |> assign(:batch_download_path, nil)
     |> assign(:upload_issue, nil)
     |> assign(:currently_compressing, nil)
     |> assign(:processing_queue, [])
     |> assign(:processing_total, 0)
     |> assign(:form, to_form(default_form_params(), as: :compression))
     |> assign(:my_path, "/video-compressor")
     |> allow_upload(:video,
       accept: @video_accept,
       max_entries: 10,
       max_file_size: @max_video_upload_size,
       auto_upload: true
     )}
  end

  @impl true
  def handle_event("validate", %{"compression" => params}, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(Map.merge(default_form_params(), params), as: :compression))
     |> maybe_clear_upload_issue()}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, socket |> cancel_upload(:video, ref) |> maybe_clear_upload_issue()}
  end

  @impl true
  def handle_event("compress", %{"compression" => params}, socket) do
    if processing?(socket.assigns.currently_compressing) do
      {:noreply, put_flash(socket, :error, gettext("Aguarde a compressao atual terminar."))}
    else
      params = Map.merge(default_form_params(), params)

      socket
      |> assign(:form, to_form(params, as: :compression))
      |> reconcile_video_uploads()
      |> continue_compress(params)
    end
  end

  defp continue_compress({:error, socket}, _params), do: {:noreply, socket}

  defp continue_compress({:ok, socket}, params) do
    case uploaded_entries(socket, :video) do
      {[], []} ->
        {:noreply,
         put_flash(socket, :error, gettext("Selecione ao menos um video antes de comprimir."))}

      {_completed, [_ | _]} ->
        {:noreply,
         put_flash(socket, :error, gettext("Aguarde o upload terminar antes de comprimir."))}

      _ ->
        {:noreply, start_compression(socket, params)}
    end
  end

  @impl true
  def handle_info({:begin_video_compression, staged_entries, params, results}, socket) do
    case staged_entries do
      [] ->
        {:noreply, finish_compression(socket, Enum.reverse(results))}

      [entry | rest] ->
        send(self(), {:run_video_compression, entry, rest, params, results})

        {:noreply,
         socket
         |> assign(:currently_compressing, entry.client_name)
         |> assign(:processing_queue, Enum.map([entry | rest], & &1.client_name))}
    end
  end

  @impl true
  def handle_info({:run_video_compression, entry, rest, params, results}, socket) do
    lv = self()

    # Keep the LiveView free for WebSocket heartbeats while ffmpeg runs.
    # Blocking the LV process on long re-encodes drops the socket in production.
    Task.start(fn ->
      result =
        try do
          compress_staged_entry(entry, params)
        rescue
          error ->
            {:error, {:compression_exception, Exception.message(error)}}
        catch
          kind, reason ->
            {:error, {:compression_crash, {kind, inspect(reason)}}}
        end

      send(lv, {:video_compression_done, result, rest, params, results})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:video_compression_done, result, rest, params, results}, socket) do
    send(self(), {:begin_video_compression, rest, params, [result | results]})
    {:noreply, socket}
  end

  defp start_compression(socket, params) do
    case stage_uploaded_entries(socket) do
      {:ok, []} ->
        put_flash(socket, :error, gettext("Selecione ao menos um video antes de comprimir."))

      {:ok, staged_entries} ->
        send(self(), {:begin_video_compression, staged_entries, params, []})

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
      consume_uploaded_entries(socket, :video, fn meta, entry ->
        stage_single_upload(meta, entry)
      end)

    case Enum.split_with(staged_entries, &match?(%{source_path: _}, &1)) do
      {good, []} ->
        {:ok, good}

      {_good, _bad} ->
        {:error, staging_error_socket(socket)}
    end
  catch
    kind, reason ->
      require Logger
      Logger.error("video compressor staging failed: #{inspect({kind, reason})}")
      {:error, staging_error_socket(socket)}
  end

  defp stage_single_upload(%{path: path}, entry) do
    output_dir =
      Path.join(System.tmp_dir!(), "rapid_tools_live/#{System.unique_integer([:positive])}")

    source_path = Path.join(output_dir, safe_client_name(entry.client_name))

    with :ok <- File.mkdir_p(output_dir),
         :ok <- File.cp(path, source_path) do
      {:ok,
       %{
         source_path: source_path,
         client_name: entry.client_name,
         output_dir: output_dir
       }}
    else
      {:error, reason} -> {:ok, {:stage_error, reason}}
    end
  end

  defp staging_error_socket(socket) do
    socket
    |> assign(:upload_issue, lost_upload_message())
    |> put_flash(:error, lost_upload_message())
  end

  defp compress_staged_entry(entry, %{
         "preset" => preset,
         "max_resolution" => max_resolution,
         "mute" => mute
       }) do
    case VideoCompressor.compress(entry.source_path,
           preset: preset,
           max_resolution: max_resolution,
           mute: mute in ["true", true],
           output_dir: entry.output_dir
         ) do
      {:ok, result} ->
        store_entry = %{
          path: result.output_path,
          filename: result.filename,
          media_type: result.media_type
        }

        case ConversionStore.put(store_entry) do
          {:ok, id} ->
            {:ok, Map.put(result, :download_path, ~p"/downloads/#{id}")}

          other ->
            {:error, {:store_failed, other}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      {:error, {:compression_exception, Exception.message(error)}}
  end

  defp finish_compression(socket, results) do
    socket =
      socket
      |> assign(:currently_compressing, nil)
      |> assign(:processing_queue, [])
      |> assign(:processing_total, 0)

    case successful_batch_results(results) do
      {:ok, successful_results} ->
        build_batch_response(
          socket,
          successful_results,
          gettext("%{count} videos compressed.", count: length(successful_results)),
          gettext("Os videos foram gerados, mas o ZIP nao pode ser criado.")
        )

      :error ->
        put_flash(socket, :error, compression_error_message(results))
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
    gettext("O upload deste video foi perdido antes da compressao. Envie o arquivo novamente.")
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

  defp compression_error_message([{:error, :ffmpeg_not_found}]),
    do: gettext("FFmpeg nao esta disponivel no servidor. Tente novamente mais tarde.")

  defp compression_error_message([{:error, {:compression_failed, _}}]),
    do:
      gettext(
        "Nao foi possivel comprimir este video. Confirme se o arquivo nao esta corrompido e tente novamente."
      )

  defp compression_error_message(_results),
    do: gettext("Os videos nao puderam ser comprimidos.")

  defp build_batch_response(socket, successful_results, success_message, zip_error_message) do
    batch_entries =
      Enum.map(successful_results, fn result ->
        %{
          path: result.output_path,
          filename: result.filename,
          media_type: result.media_type
        }
      end)

    with {:ok, batch_id} <- ConversionStore.put_batch(batch_entries),
         {:ok, zip_entry} <- ZipArchive.build(batch_id, batch_entries),
         {:ok, zip_id} <- ConversionStore.put(zip_entry) do
      socket
      |> assign(:results, successful_results)
      |> assign(:batch_download_path, ~p"/downloads/#{zip_id}")
      |> put_flash(:info, success_message)
    else
      _ ->
        socket
        |> assign(:results, successful_results)
        |> assign(:batch_download_path, nil)
        |> put_flash(:error, zip_error_message)
    end
  end

  defp default_form_params do
    %{"preset" => "balanced", "max_resolution" => "original", "mute" => "false"}
  end

  defp safe_client_name(name) when is_binary(name) do
    name
    |> Path.basename()
    |> String.replace(~r/[\x00-\x1F\x7F]/, "_")
    |> case do
      "" -> "video"
      safe -> safe
    end
  end

  defp safe_client_name(_), do: "video"

  defp completed_upload_count(entries), do: Enum.count(entries, &(&1.progress == 100))
  defp upload_in_progress?(entries), do: Enum.any?(entries, &(&1.progress < 100))
  defp processing?(currently_compressing), do: currently_compressing != nil

  defp processing_position(assigns) do
    queue_count = length(assigns.processing_queue)

    if assigns.processing_total > 0 and queue_count > 0 do
      assigns.processing_total - queue_count + 1
    else
      0
    end
  end

  defp upload_summary(entries, currently_compressing) do
    total = length(entries)
    completed = completed_upload_count(entries)

    cond do
      processing?(currently_compressing) ->
        gettext(
          "Fila enviada para compressao. O video atual aparece com loader e o restante fica na sequencia."
        )

      total == 0 ->
        gettext("Nenhum video selecionado ainda.")

      upload_in_progress?(entries) ->
        gettext(
          "%{total} videos in queue. %{completed}/%{total} finished so far, the rest are still uploading.",
          total: total,
          completed: completed
        )

      true ->
        gettext("%{count} videos selected. All of them appear in this scrollable list.",
          count: total
        )
    end
  end

  defp upload_status_message(entries, currently_compressing, upload_issue) do
    cond do
      upload_issue ->
        upload_issue

      processing?(currently_compressing) ->
        gettext("Compressao em andamento. Acompanhe qual arquivo esta sendo processado agora.")

      entries == [] ->
        gettext("Selecione videos para reduzir tamanho sem sair do navegador.")

      upload_in_progress?(entries) ->
        gettext("Enviando videos para o servidor. Aguarde todos chegarem a 100%.")

      true ->
        gettext("Uploads concluidos. Agora voce pode gerar as versoes comprimidas.")
    end
  end

  defp upload_error_message(:not_accepted),
    do: gettext("Formato nao aceito. Envie MP4, MOV, WEBM, MKV ou AVI.")

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
      main_class="px-0 pb-0 pt-0 sm:px-0 lg:px-0"
      content_class="w-full"
      show_header={false}
    >
      <section class="h-screen overflow-hidden bg-[radial-gradient(circle_at_top_left,_rgba(251,146,60,0.18),_transparent_30%),radial-gradient(circle_at_bottom_right,_rgba(244,63,94,0.14),_transparent_28%),linear-gradient(180deg,_rgba(255,247,237,1)_0%,_rgba(255,255,255,1)_52%,_rgba(255,241,242,1)_100%)]">
        <div class="mx-auto max-w-7xl h-full px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)] h-full">
            <.tool_sidebar
              tools={@tools}
              current_locale={@current_locale}
              redirect_to={@my_path}
              theme={%{sidebar_border_class: "border-rose-100", accent_class: "text-rose-700"}}
            />

            <div class="space-y-6 overflow-y-auto">
              <div class="space-y-4 px-2 py-2">
                <span class="inline-flex items-center rounded-full border border-rose-200 bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-rose-700">
                  {gettext("Video optimization")}
                </span>
                <h1 class="text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
                  {gettext("Compress videos for sharing")}
                </h1>
                <p class="max-w-3xl text-base text-slate-600 sm:text-lg">
                  {gettext(
                    "Shrink heavy uploads for email, WhatsApp, landing pages, and client approvals while keeping playback compatible."
                  )}
                </p>
                <p class="text-sm text-slate-500">
                  {gettext(
                    "Escolha um preset de compressao, limite de resolucao e, se quiser, remova o audio."
                  )}
                </p>
              </div>

              <div class="grid gap-6 xl:grid-cols-[1.35fr_0.65fr]">
                <div class="rounded-[2rem] border border-white/70 bg-white p-6 shadow-[0_24px_60px_rgba(15,23,42,0.08)]">
                  <.form
                    for={@form}
                    id="video-compressor-form"
                    phx-change="validate"
                    phx-submit="compress"
                    class="space-y-6"
                  >
                    <div
                      id="video-compressor-drop-zone"
                      phx-drop-target={@uploads.video.ref}
                      class="rounded-[1.75rem] border border-dashed border-rose-200 bg-rose-50/60 p-5"
                    >
                      <div class="space-y-2">
                        <label
                          for="video-compressor-upload"
                          class="text-sm font-semibold text-slate-900"
                        >
                          {gettext("Videos de origem")}
                        </label>
                        <.live_file_input
                          upload={@uploads.video}
                          id="video-compressor-upload"
                          class="block w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700 shadow-sm transition file:mr-4 file:rounded-xl file:border-0 file:bg-slate-950 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-white hover:border-rose-300"
                        />
                        <p class="text-sm text-slate-500">
                          {gettext("Entradas aceitas: MP4, MOV, WEBM e AVI. Ate 150 MB por video.")}
                        </p>
                      </div>

                      <div
                        :if={@currently_compressing}
                        id="video-currently-compressing"
                        class="mt-4 rounded-2xl border border-rose-200 bg-white px-4 py-3"
                      >
                        <div class="flex items-center gap-3">
                          <span class="loading loading-spinner loading-sm text-rose-600"></span>
                          <div class="min-w-0">
                            <p class="text-sm font-semibold text-slate-900">
                              {gettext("Comprimindo agora")}
                            </p>
                            <p class="truncate text-sm text-slate-600">
                              {@currently_compressing}
                            </p>
                            <p class="mt-1 text-xs text-slate-500">
                              {gettext("%{current} of %{total} videos",
                                current: processing_position(assigns),
                                total: @processing_total
                              )}
                            </p>
                          </div>
                        </div>
                      </div>

                      <div
                        id="video-compressor-upload-list"
                        class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                      >
                        <div class="sticky top-0 z-10 rounded-2xl border border-rose-100 bg-rose-50/95 px-4 py-3 text-sm font-medium text-rose-900 backdrop-blur">
                          {upload_summary(@uploads.video.entries, @currently_compressing)}
                        </div>
                        <div
                          :for={entry <- @uploads.video.entries}
                          class="flex items-center gap-3 rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700"
                        >
                          <div class="min-w-0 flex-1 pr-4">
                            <p class="truncate font-medium">{entry.client_name}</p>
                            <div class="mt-2 h-2 rounded-full bg-slate-100">
                              <div
                                class="h-2 rounded-full bg-rose-500 transition-all"
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
                            {if entry.progress == 100,
                              do: gettext("pronto"),
                              else: "#{entry.progress}%"}
                          </span>
                          <button
                            type="button"
                            phx-click="cancel-upload"
                            phx-value-ref={entry.ref}
                            disabled={processing?(@currently_compressing)}
                            aria-label={gettext("Remove %{filename}", filename: entry.client_name)}
                            class="inline-flex size-8 shrink-0 items-center justify-center rounded-full border border-slate-200 text-sm font-bold text-slate-500 transition hover:border-red-200 hover:bg-red-50 hover:text-red-600 disabled:cursor-not-allowed disabled:opacity-50"
                          >
                            X
                          </button>
                        </div>
                      </div>
                    </div>

                    <div class="grid gap-4 md:grid-cols-2">
                      <.input
                        field={@form[:preset]}
                        type="select"
                        label={gettext("Preset")}
                        options={[
                          {gettext("Small size"), "small"},
                          {gettext("Balanced"), "balanced"},
                          {gettext("High quality"), "high"}
                        ]}
                      />
                      <.input
                        field={@form[:max_resolution]}
                        type="select"
                        label={gettext("Resolucao maxima")}
                        options={[
                          {gettext("Keep original"), "original"},
                          {"1080p", "1080"},
                          {"720p", "720"},
                          {"480p", "480"}
                        ]}
                      />
                    </div>

                    <label class="flex items-center gap-3 rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-700">
                      <input
                        type="checkbox"
                        name="compression[mute]"
                        value="true"
                        checked={@form[:mute].value in ["true", true]}
                        class="checkbox checkbox-sm"
                      />
                      <span>{gettext("Remove audio track")}</span>
                    </label>

                    <button
                      type="submit"
                      id="video-compress-button"
                      phx-disable-with={gettext("Compressing videos...")}
                      disabled={
                        @uploads.video.entries == [] ||
                          upload_in_progress?(@uploads.video.entries) ||
                          processing?(@currently_compressing)
                      }
                      class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-rose-700 disabled:cursor-wait disabled:opacity-90"
                    >
                      <span>{gettext("Comprimir videos")}</span>
                    </button>

                    <p id="video-compressor-status" class="text-sm text-slate-500">
                      {upload_status_message(
                        @uploads.video.entries,
                        @currently_compressing,
                        @upload_issue
                      )}
                    </p>
                  </.form>
                </div>

                <aside class="rounded-[2rem] border border-white/70 bg-slate-950 p-6 text-white shadow-[0_24px_60px_rgba(15,23,42,0.16)]">
                  <div :if={@results != []} class="space-y-4">
                    <p class="text-sm font-semibold uppercase tracking-[0.25em] text-rose-300">
                      {gettext("%{count} videos ready", count: length(@results))}
                    </p>
                    <a
                      :if={@batch_download_path}
                      href={@batch_download_path}
                      class="inline-flex w-full items-center justify-center rounded-2xl bg-rose-400 px-4 py-3 text-sm font-semibold text-slate-950 transition hover:bg-rose-300"
                    >
                      {gettext("Baixar pacote ZIP")}
                    </a>
                    <div class="space-y-3">
                      <div
                        :for={result <- @results}
                        class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4"
                      >
                        <p class="font-semibold">{result.filename}</p>
                        <p class="mt-1 text-sm text-slate-300">
                          {String.capitalize(result.preset)} preset, {result.max_resolution} max
                        </p>
                        <a
                          href={result.download_path}
                          class="mt-3 inline-flex w-full items-center justify-center rounded-2xl border border-white/10 bg-white/10 px-4 py-3 text-sm font-semibold text-white transition hover:bg-white/20"
                        >
                          {gettext("Baixar video")}
                        </a>
                      </div>
                    </div>
                  </div>

                  <div :if={@results == []} class="space-y-4">
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold uppercase tracking-[0.25em] text-rose-300">
                        {gettext("Small size")}
                      </p>
                      <p class="mt-3 text-sm text-slate-300">
                        {gettext(
                          "Preset focado em arquivos leves para upload, review e compartilhamento rapido."
                        )}
                      </p>
                    </div>
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold text-white">{gettext("Formato final")}</p>
                      <p class="mt-2 text-sm text-slate-300">
                        {gettext("MP4 otimizado com H.264 e AAC para ampla compatibilidade.")}
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
