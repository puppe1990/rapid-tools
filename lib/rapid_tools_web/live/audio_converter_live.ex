defmodule RapidToolsWeb.AudioConverterLive do
  use RapidToolsWeb, :live_view

  alias RapidTools.AudioConverter
  alias RapidTools.ConversionStore
  alias RapidTools.ZipArchive
  alias RapidToolsWeb.ToolNavigation

  @audio_accept ~w(.mp3 .wav .ogg .aac)

  @impl true
  def mount(_params, session, socket) do
    locale =
      Locale.set_gettext_locale(
        session["locale"] || socket.assigns[:current_locale] || Locale.default_locale()
      )

    form =
      to_form(
        %{"target_format" => default_target_format()},
        as: :conversion
      )

    {:ok,
     socket
     |> assign(:current_locale, locale)
     |> assign(:formats, AudioConverter.supported_formats())
     |> assign(:tools, ToolNavigation.tools("audio"))
     |> assign(:form, form)
     |> assign(:results, [])
     |> assign(:batch_download_path, nil)
     |> assign(:my_path, "/audio-converter")
     |> allow_upload(:audio, accept: @audio_accept, max_entries: 10, auto_upload: true)}
  end

  @impl true
  def handle_event("validate", %{"conversion" => conversion_params}, socket) do
    {:noreply, assign(socket, :form, to_form(conversion_params, as: :conversion))}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :audio, ref)}
  end

  @impl true
  def handle_event("convert", %{"conversion" => %{"target_format" => target_format}}, socket) do
    case uploaded_entries(socket, :audio) do
      {[], []} ->
        {:noreply, put_flash(socket, :error, gettext("Selecione um audio antes de converter."))}

      {_completed, [_ | _]} ->
        {:noreply,
         put_flash(socket, :error, gettext("Aguarde o upload terminar antes de converter."))}

      _ ->
        {:noreply, convert_upload(socket, target_format)}
    end
  end

  defp convert_upload(socket, target_format) do
    results =
      consume_uploaded_entries(socket, :audio, fn %{path: path}, entry ->
        output_dir =
          Path.join(
            System.tmp_dir!(),
            "rapid_tools_live/#{System.unique_integer([:positive])}"
          )

        File.mkdir_p!(output_dir)

        source_path = Path.join(output_dir, entry.client_name)
        File.cp!(path, source_path)

        case AudioConverter.convert(source_path, target_format, output_dir: output_dir) do
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
          gettext("%{count} audio files converted.", count: length(successful_results)),
          gettext("Os audios foram convertidos, mas o ZIP nao pode ser gerado.")
        )

      :error ->
        put_flash(socket, :error, gettext("O audio nao pode ser convertido."))
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

  defp upload_status_message(entries) do
    cond do
      entries == [] ->
        gettext("Selecione um ou mais audios para habilitar a conversao.")

      upload_in_progress?(entries) ->
        gettext("Enviando audios para o servidor. Aguarde todos chegarem a 100%.")

      true ->
        gettext("Uploads concluidos. Agora voce pode converter em lote.")
    end
  end

  defp upload_summary(entries) do
    total = length(entries)
    completed = completed_upload_count(entries)

    cond do
      total == 0 ->
        gettext("Nenhum audio selecionado ainda.")

      upload_in_progress?(entries) ->
        gettext(
          "%{total} audio files in queue. %{completed}/%{total} finished so far, the rest are still uploading.",
          total: total,
          completed: completed
        )

      true ->
        gettext("%{count} audio files selected. All of them appear in this scrollable list.",
          count: total
        )
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      main_class="px-0 pb-8 pt-0 sm:px-0 lg:px-0"
      content_class="w-full"
      show_header={false}
    >
      <section class="min-h-screen bg-[radial-gradient(circle_at_top_left,_rgba(16,185,129,0.16),_transparent_28%),radial-gradient(circle_at_bottom_right,_rgba(59,130,246,0.12),_transparent_26%),linear-gradient(180deg,_rgba(244,248,246,1)_0%,_rgba(255,255,255,1)_50%,_rgba(241,247,249,1)_100%)]">
        <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)]">
            <.tool_sidebar
              tools={@tools}
              current_locale={@current_locale}
              redirect_to={@my_path}
              theme={%{sidebar_border_class: "border-emerald-100", accent_class: "text-emerald-600"}}
            />

            <div class="space-y-6">
              <div class="space-y-4 px-2 py-2">
                <span class="inline-flex items-center rounded-full border border-emerald-200 bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-emerald-700">
                  {gettext("Audio workflow")}
                </span>
                <h1 class="text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
                  {gettext("Audio Converter")}
                </h1>
                <p class="max-w-3xl text-base text-slate-600 sm:text-lg">
                  {gettext(
                    "Converta arquivos de audio para MP3, WAV, OGG, AAC e FLAC com downloads individuais ou em lote."
                  )}
                </p>
                <p class="text-sm text-slate-500">
                  {gettext(
                    "Ideal para podcasts, trilhas, cortes para social e distribuicao multiplataforma."
                  )}
                </p>
              </div>

              <div id="audio-converter-panel" class="grid gap-6 xl:grid-cols-[1.35fr_0.65fr]">
                <div class="relative rounded-[2rem] border border-white/70 bg-white p-6 shadow-[0_24px_60px_rgba(15,23,42,0.08)]">
                  <.form
                    for={@form}
                    id="audio-converter-form"
                    phx-change="validate"
                    phx-submit="convert"
                    class="space-y-6"
                  >
                    <div class="pointer-events-none absolute inset-0 z-10 hidden items-center justify-center rounded-[2rem] bg-white/80 backdrop-blur-sm phx-submit-loading:flex">
                      <div class="flex items-center gap-3 rounded-full border border-emerald-200 bg-white px-5 py-3 shadow-lg">
                        <span class="inline-block size-5 animate-spin rounded-full border-2 border-emerald-200 border-t-emerald-600" />
                        <div>
                          <p class="text-sm font-semibold text-slate-950">
                            {gettext("Convertendo audio")}
                          </p>
                          <p class="text-xs text-slate-500">
                            {gettext("Isso pode levar alguns segundos.")}
                          </p>
                        </div>
                      </div>
                    </div>

                    <div class="rounded-[1.75rem] border border-dashed border-emerald-200 bg-emerald-50/60 p-5">
                      <div class="space-y-2">
                        <label for="audio-upload" class="text-sm font-semibold text-slate-900">
                          {gettext("Audio de origem")}
                        </label>
                        <.live_file_input
                          upload={@uploads.audio}
                          id="audio-upload"
                          class="block w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700 shadow-sm transition file:mr-4 file:rounded-xl file:border-0 file:bg-slate-950 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-white hover:border-emerald-300"
                        />
                        <p class="text-sm text-slate-500">
                          {gettext("Entradas aceitas: MP3, WAV, OGG e AAC.")}
                        </p>
                      </div>

                      <div
                        id="audio-upload-list"
                        class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                      >
                        <div class="sticky top-0 z-10 rounded-2xl border border-emerald-100 bg-emerald-50/95 px-4 py-3 text-sm font-medium text-emerald-900 backdrop-blur">
                          {upload_summary(@uploads.audio.entries)}
                        </div>
                        <div
                          :for={entry <- @uploads.audio.entries}
                          class="flex items-center gap-3 rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700"
                        >
                          <div class="min-w-0 flex-1 pr-4">
                            <p class="truncate font-medium">{entry.client_name}</p>
                            <div class="mt-2 h-2 rounded-full bg-slate-100">
                              <div
                                class="h-2 rounded-full bg-emerald-400 transition-all"
                                style={"width: #{entry.progress}%"}
                              />
                            </div>
                          </div>
                          <span class="text-xs uppercase tracking-[0.2em] text-slate-400">
                            <%= if entry.progress == 100 do %>
                              {gettext("pronto")}
                            <% else %>
                              {entry.progress}%
                            <% end %>
                          </span>
                          <button
                            type="button"
                            phx-click="cancel-upload"
                            phx-value-ref={entry.ref}
                            aria-label={gettext("Remove %{filename}", filename: entry.client_name)}
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
                      id="audio-target-format"
                      label={gettext("Formato de destino")}
                      options={Enum.map(@formats, &{String.upcase(&1), &1})}
                      class="w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none transition focus:border-emerald-400"
                    />

                    <button
                      type="submit"
                      id="audio-convert-button"
                      phx-disable-with={gettext("Converting audio...")}
                      disabled={
                        @uploads.audio.entries == [] || upload_in_progress?(@uploads.audio.entries)
                      }
                      class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-emerald-700 disabled:cursor-wait disabled:opacity-90"
                    >
                      <span class="inline-block size-4 animate-spin rounded-full border-2 border-white/30 border-t-white opacity-0 phx-submit-loading:opacity-100" />
                      <span>{gettext("Converter audio")}</span>
                    </button>

                    <p id="audio-converter-status" class="text-sm text-slate-500">
                      {upload_status_message(@uploads.audio.entries)}
                    </p>
                  </.form>
                </div>

                <aside class="rounded-[2rem] border border-white/70 bg-slate-950 p-6 text-white shadow-[0_24px_60px_rgba(15,23,42,0.16)]">
                  <div :if={@results != []} class="space-y-4">
                    <p class="text-sm font-semibold uppercase tracking-[0.25em] text-emerald-300">
                      {gettext("%{count} audio files converted", count: length(@results))}
                    </p>
                    <a
                      :if={@batch_download_path}
                      href={@batch_download_path}
                      class="inline-flex w-full items-center justify-center rounded-2xl bg-emerald-400 px-4 py-3 text-sm font-semibold text-slate-950 transition hover:bg-emerald-300"
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
                          {gettext("Saida em")} {String.upcase(result.target_format)}
                        </p>
                        <a
                          href={result.download_path}
                          class="mt-3 inline-flex w-full items-center justify-center rounded-2xl border border-white/10 bg-white/10 px-4 py-3 text-sm font-semibold text-white transition hover:bg-white/20"
                        >
                          {gettext("Baixar arquivo convertido")}
                        </a>
                      </div>
                    </div>
                  </div>
                  <div :if={@results == []} class="space-y-4">
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold uppercase tracking-[0.25em] text-emerald-300">
                        {gettext("Formatos populares")}
                      </p>
                      <p class="mt-3 text-sm text-slate-300">
                        {gettext(
                          "MP3 para distribuicao ampla, WAV para edicao, OGG para web, AAC para compatibilidade mobile e FLAC para masters sem perdas."
                        )}
                      </p>
                    </div>
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold text-white">{gettext("Saidas suportadas")}</p>
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
