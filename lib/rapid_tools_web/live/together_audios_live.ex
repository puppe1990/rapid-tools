defmodule RapidToolsWeb.TogetherAudiosLive do
  use RapidToolsWeb, :live_view

  alias RapidTools.AudioJoiner
  alias RapidTools.ConversionStore
  alias RapidToolsWeb.ToolNavigation

  @audio_accept ~w(.mp3 .wav .ogg .aac)

  @impl true
  def mount(_params, _session, socket) do
    form =
      to_form(
        %{"target_format" => default_target_format()},
        as: :conversion
      )

    {:ok,
     socket
     |> assign(:formats, AudioJoiner.supported_formats())
     |> assign(:tools, ToolNavigation.tools("together-audios"))
     |> assign(:form, form)
     |> assign(:result, nil)
     |> allow_upload(:audio, accept: @audio_accept, max_entries: 100, auto_upload: true)}
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
  def handle_event("join", %{"conversion" => %{"target_format" => target_format}}, socket) do
    case uploaded_entries(socket, :audio) do
      {[], []} ->
        {:noreply, put_flash(socket, :error, "Selecione pelo menos dois audios para unir.")}

      {_completed, [_ | _]} ->
        {:noreply, put_flash(socket, :error, "Aguarde o upload terminar antes de unir.")}

      {completed, []} when length(completed) < 2 ->
        {:noreply, put_flash(socket, :error, "Selecione pelo menos dois audios para unir.")}

      _ ->
        {:noreply, join_uploads(socket, target_format)}
    end
  end

  defp join_uploads(socket, target_format) do
    output_dir =
      Path.join(
        System.tmp_dir!(),
        "rapid_tools_live/#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(output_dir)

    source_paths =
      consume_uploaded_entries(socket, :audio, fn %{path: path}, entry ->
        source_path = Path.join(output_dir, entry.client_name)
        File.cp!(path, source_path)
        {:ok, source_path}
      end)

    case AudioJoiner.join(source_paths, target_format, output_dir: output_dir) do
      {:ok, result} ->
        store_entry = %{
          path: result.output_path,
          filename: result.filename,
          media_type: result.media_type
        }

        {:ok, id} = ConversionStore.put(store_entry)

        joined_result =
          Map.merge(result, %{
            download_path: ~p"/downloads/#{id}",
            source_count: length(source_paths)
          })

        socket
        |> assign(:result, joined_result)
        |> put_flash(:info, "#{length(source_paths)} audios unidos com sucesso.")

      {:error, :not_enough_source_files} ->
        put_flash(socket, :error, "Selecione pelo menos dois audios para unir.")

      {:error, _reason} ->
        put_flash(socket, :error, "Os audios nao puderam ser unidos.")
    end
  end

  defp default_target_format, do: "mp3"

  defp completed_upload_count(entries) do
    Enum.count(entries, &(&1.progress == 100))
  end

  defp upload_in_progress?(entries) do
    Enum.any?(entries, &(&1.progress < 100))
  end

  defp enough_completed_uploads?(entries) do
    completed_upload_count(entries) >= 2
  end

  defp upload_status_message(entries) do
    cond do
      entries == [] ->
        "Selecione pelo menos dois audios para habilitar a uniao."

      upload_in_progress?(entries) ->
        "Enviando arquivos para o servidor. Aguarde todos chegarem a 100%."

      !enough_completed_uploads?(entries) ->
        "Falta pelo menos mais um audio para iniciar a uniao."

      true ->
        "Uploads concluidos. Agora voce pode juntar os audios."
    end
  end

  defp upload_summary(entries) do
    total = length(entries)
    completed = completed_upload_count(entries)

    cond do
      total == 0 ->
        "Nenhum audio selecionado ainda."

      upload_in_progress?(entries) ->
        "#{total} audios na fila. #{completed}/#{total} concluidos ate agora, o restante ainda esta enviando."

      true ->
        "#{total} audios selecionados. Todos aparecem nesta caixa com scroll."
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
      <section class="min-h-screen bg-[radial-gradient(circle_at_top_left,_rgba(251,146,60,0.16),_transparent_28%),radial-gradient(circle_at_bottom_right,_rgba(20,184,166,0.14),_transparent_26%),linear-gradient(180deg,_rgba(248,246,242,1)_0%,_rgba(255,255,255,1)_52%,_rgba(241,248,247,1)_100%)]">
        <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)]">
            <aside class="rounded-[2rem] border border-amber-100 bg-white/85 p-5 shadow-[0_18px_50px_rgba(15,23,42,0.08)] backdrop-blur">
              <div class="space-y-6">
                <div class="space-y-2">
                  <p class="text-sm font-semibold uppercase tracking-[0.3em] text-amber-600">
                    Rapid Tools
                  </p>
                  <div>
                    <h2 class="text-2xl font-black tracking-tight text-slate-950">Tools</h2>
                    <p class="mt-1 text-sm text-slate-600">
                      Fluxos para conversao e montagem de midia.
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
                <span class="inline-flex items-center rounded-full border border-amber-200 bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-amber-700">
                  Audio assembly
                </span>
                <h1 class="text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
                  Together Audios
                </h1>
                <p class="max-w-3xl text-base text-slate-600 sm:text-lg">
                  Junte varios arquivos de audio em uma unica faixa final.
                </p>
                <p class="text-sm text-slate-500">
                  Envie ao menos duas faixas, defina o formato final e baixe um unico arquivo pronto para publicar.
                </p>
              </div>

              <div id="together-audios-panel" class="grid gap-6 xl:grid-cols-[1.35fr_0.65fr]">
                <div class="relative rounded-[2rem] border border-white/70 bg-white p-6 shadow-[0_24px_60px_rgba(15,23,42,0.08)]">
                  <.form
                    for={@form}
                    id="together-audios-form"
                    phx-change="validate"
                    phx-submit="join"
                    class="space-y-6"
                  >
                    <div class="pointer-events-none absolute inset-0 z-10 hidden items-center justify-center rounded-[2rem] bg-white/80 backdrop-blur-sm phx-submit-loading:flex">
                      <div class="flex items-center gap-3 rounded-full border border-amber-200 bg-white px-5 py-3 shadow-lg">
                        <span class="inline-block size-5 animate-spin rounded-full border-2 border-amber-200 border-t-amber-600" />
                        <div>
                          <p class="text-sm font-semibold text-slate-950">Unindo audios</p>
                          <p class="text-xs text-slate-500">Isso pode levar alguns segundos.</p>
                        </div>
                      </div>
                    </div>

                    <div class="rounded-[1.75rem] border border-dashed border-amber-200 bg-amber-50/60 p-5">
                      <div class="space-y-2">
                        <label
                          for="together-audio-upload"
                          class="text-sm font-semibold text-slate-900"
                        >
                          Audios de origem
                        </label>
                        <.live_file_input
                          upload={@uploads.audio}
                          id="together-audio-upload"
                          class="block w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700 shadow-sm transition file:mr-4 file:rounded-xl file:border-0 file:bg-slate-950 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-white hover:border-amber-300"
                        />
                        <p class="text-sm text-slate-500">
                          Entradas aceitas: MP3, WAV, OGG e AAC. Selecione ao menos dois arquivos.
                        </p>
                      </div>

                      <div
                        id="together-audios-upload-list"
                        class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                      >
                        <div class="sticky top-0 z-10 rounded-2xl border border-amber-100 bg-amber-50/95 px-4 py-3 text-sm font-medium text-amber-900 backdrop-blur">
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
                                class="h-2 rounded-full bg-amber-400 transition-all"
                                style={"width: #{entry.progress}%"}
                              />
                            </div>
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
                      id="together-audios-target-format"
                      label="Formato final"
                      options={Enum.map(@formats, &{String.upcase(&1), &1})}
                      class="w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none transition focus:border-amber-400"
                    />

                    <button
                      type="submit"
                      id="together-audios-button"
                      phx-disable-with="Unindo audios..."
                      disabled={
                        !enough_completed_uploads?(@uploads.audio.entries) ||
                          upload_in_progress?(@uploads.audio.entries)
                      }
                      class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-amber-600 disabled:cursor-wait disabled:opacity-90"
                    >
                      <span class="inline-block size-4 animate-spin rounded-full border-2 border-white/30 border-t-white opacity-0 phx-submit-loading:opacity-100" />
                      <span>Juntar audios</span>
                    </button>

                    <p
                      id="together-audios-status"
                      class="text-sm text-slate-500"
                    >
                      {upload_status_message(@uploads.audio.entries)}
                    </p>
                  </.form>
                </div>

                <aside class="rounded-[2rem] border border-white/70 bg-slate-950 p-6 text-white shadow-[0_24px_60px_rgba(15,23,42,0.16)]">
                  <div :if={@result} class="space-y-4">
                    <p class="text-sm font-semibold uppercase tracking-[0.25em] text-amber-300">
                      Arquivo final gerado
                    </p>
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="font-semibold">{@result.filename}</p>
                      <p class="mt-1 text-sm text-slate-300">
                        {@result.source_count} audios unidos em {String.upcase(@result.target_format)}
                      </p>
                      <a
                        href={@result.download_path}
                        class="mt-3 inline-flex w-full items-center justify-center rounded-2xl bg-amber-400 px-4 py-3 text-sm font-semibold text-slate-950 transition hover:bg-amber-300"
                      >
                        Baixar audio final
                      </a>
                    </div>
                  </div>
                  <div :if={!@result} class="space-y-4">
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold uppercase tracking-[0.25em] text-amber-300">
                        Como funciona
                      </p>
                      <p class="mt-3 text-sm text-slate-300">
                        O Rapid Tools combina as faixas na ordem em que foram enviadas e exporta um unico arquivo final.
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
