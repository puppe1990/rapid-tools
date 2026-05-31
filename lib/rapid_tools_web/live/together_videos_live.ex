defmodule RapidToolsWeb.TogetherVideosLive do
  use RapidToolsWeb, :live_view

  alias RapidTools.ConversionStore
  alias RapidTools.VideoJoiner
  alias RapidToolsWeb.ToolNavigation

  @video_accept ~w(.mp4 .mov .webm .mkv .avi)
  @max_video_upload_size 150_000_000

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
     |> assign(:formats, VideoJoiner.supported_formats())
     |> assign(:tools, ToolNavigation.tools("together-videos"))
     |> assign(:form, form)
     |> assign(:result, nil)
     |> assign(:video_order, [])
     |> assign(:my_path, "/together-videos")
     |> allow_upload(:video,
       accept: @video_accept,
       max_entries: 100,
       max_file_size: @max_video_upload_size,
       auto_upload: true
     )}
  end

  @impl true
  def handle_event("validate", %{"conversion" => conversion_params}, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(conversion_params, as: :conversion))
     |> sync_video_order(socket.assigns.uploads.video.entries)}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    entries = Enum.reject(socket.assigns.uploads.video.entries, &(&1.ref == ref))

    {:noreply,
     socket
     |> cancel_upload(:video, ref)
     |> assign(:video_order, remove_ref(socket.assigns.video_order, ref))
     |> sync_video_order(entries)}
  end

  @impl true
  def handle_event("move-up", %{"ref" => ref}, socket) do
    synced_order =
      synced_video_order(socket.assigns.video_order, socket.assigns.uploads.video.entries)

    {:noreply, assign(socket, :video_order, move_ref(synced_order, ref, -1))}
  end

  @impl true
  def handle_event("move-down", %{"ref" => ref}, socket) do
    synced_order =
      synced_video_order(socket.assigns.video_order, socket.assigns.uploads.video.entries)

    {:noreply, assign(socket, :video_order, move_ref(synced_order, ref, 1))}
  end

  @impl true
  def handle_event("join", %{"conversion" => %{"target_format" => target_format}}, socket) do
    case uploaded_entries(socket, :video) do
      {[], []} ->
        {:noreply,
         put_flash(socket, :error, gettext("Selecione pelo menos dois videos para unir."))}

      {_completed, [_ | _]} ->
        {:noreply, put_flash(socket, :error, gettext("Aguarde o upload terminar antes de unir."))}

      {completed, []} when length(completed) < 2 ->
        {:noreply,
         put_flash(socket, :error, gettext("Selecione pelo menos dois videos para unir."))}

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

    ordered_refs =
      synced_video_order(socket.assigns.video_order, socket.assigns.uploads.video.entries)

    source_paths =
      consume_uploaded_entries(socket, :video, fn %{path: path}, entry ->
        source_path = Path.join(output_dir, entry.client_name)
        File.cp!(path, source_path)
        {:ok, {entry.ref, source_path}}
      end)
      |> order_source_paths(ordered_refs)

    case VideoJoiner.join(source_paths, target_format, output_dir: output_dir) do
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
        |> put_flash(
          :info,
          gettext("%{count} video files joined successfully.", count: length(source_paths))
        )

      {:error, :not_enough_source_files} ->
        put_flash(socket, :error, gettext("Selecione pelo menos dois videos para unir."))

      {:error, _reason} ->
        put_flash(socket, :error, gettext("Os videos nao puderam ser unidos."))
    end
  end

  defp default_target_format, do: "mp4"

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
        gettext("Selecione pelo menos dois videos para habilitar a uniao.")

      upload_in_progress?(entries) ->
        gettext("Enviando arquivos para o servidor. Aguarde todos chegarem a 100%.")

      !enough_completed_uploads?(entries) ->
        gettext("Falta pelo menos mais um video para iniciar a uniao.")

      true ->
        gettext("Uploads concluidos. Agora voce pode juntar os videos.")
    end
  end

  defp upload_summary(entries) do
    total = length(entries)
    completed = completed_upload_count(entries)

    cond do
      total == 0 ->
        gettext("Nenhum video selecionado ainda.")

      upload_in_progress?(entries) ->
        gettext(
          "%{total} video files in queue. %{completed}/%{total} finished so far, the rest are still uploading.",
          total: total,
          completed: completed
        )

      true ->
        gettext("%{count} video files selected. All of them appear in this scrollable list.",
          count: total
        )
    end
  end

  defp sync_video_order(socket, entries) do
    assign(socket, :video_order, synced_video_order(socket.assigns.video_order, entries))
  end

  defp synced_video_order(current_order, entries) do
    entry_refs = Enum.map(entries, & &1.ref)
    kept_refs = Enum.filter(current_order, &(&1 in entry_refs))
    new_refs = Enum.reject(entry_refs, &(&1 in kept_refs))
    kept_refs ++ new_refs
  end

  defp ordered_entries(entries, video_order) do
    order = synced_video_order(video_order, entries)
    order_index = Map.new(Enum.with_index(order))
    Enum.sort_by(entries, &Map.get(order_index, &1.ref, length(order)))
  end

  defp move_ref(order, ref, direction) do
    case Enum.find_index(order, &(&1 == ref)) do
      nil ->
        order

      index ->
        target_index = index + direction

        if target_index < 0 or target_index >= length(order) do
          order
        else
          value = Enum.at(order, index)

          order
          |> List.replace_at(index, Enum.at(order, target_index))
          |> List.replace_at(target_index, value)
        end
    end
  end

  defp remove_ref(order, ref), do: Enum.reject(order, &(&1 == ref))

  defp order_source_paths(source_paths, ordered_refs) do
    order_index = Map.new(Enum.with_index(ordered_refs))

    source_paths
    |> Enum.sort_by(fn {ref, _path} -> Map.get(order_index, ref, length(ordered_refs)) end)
    |> Enum.map(fn {_ref, path} -> path end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      main_class="px-0 pb-0 pt-0 sm:px-0 lg:px-0"
      content_class="w-full"
      show_header={false}
    >
      <section class="h-screen overflow-hidden bg-[radial-gradient(circle_at_top_left,_rgba(236,72,153,0.16),_transparent_28%),radial-gradient(circle_at_bottom_right,_rgba(20,184,166,0.14),_transparent_26%),linear-gradient(180deg,_rgba(248,246,242,1)_0%,_rgba(255,255,255,1)_52%,_rgba(241,248,247,1)_100%)]">
        <div class="mx-auto max-w-7xl h-full px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)] h-full">
            <.tool_sidebar
              tools={@tools}
              current_locale={@current_locale}
              redirect_to={@my_path}
              theme={%{sidebar_border_class: "border-pink-100", accent_class: "text-pink-600"}}
            />

            <div class="space-y-6 overflow-y-auto">
              <div class="space-y-4 px-2 py-2">
                <span class="inline-flex items-center rounded-full border border-pink-200 bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-pink-700">
                  {gettext("Video assembly")}
                </span>
                <h1 class="text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
                  {gettext("Together Videos")}
                </h1>
                <p class="max-w-3xl text-base text-slate-600 sm:text-lg">
                  {gettext("Junte varios arquivos de video em uma unica faixa final.")}
                </p>
                <p class="text-sm text-slate-500">
                  {gettext(
                    "Envie ao menos duas faixas, defina o formato final e baixe um unico arquivo pronto para publicar."
                  )}
                </p>
              </div>

              <div id="together-videos-panel" class="grid gap-6 xl:grid-cols-[1.35fr_0.65fr]">
                <div class="relative rounded-[2rem] border border-white/70 bg-white p-6 shadow-[0_24px_60px_rgba(15,23,42,0.08)]">
                  <.form
                    for={@form}
                    id="together-videos-form"
                    phx-change="validate"
                    phx-submit="join"
                    class="space-y-6"
                  >
                    <div class="pointer-events-none absolute inset-0 z-10 hidden items-center justify-center rounded-[2rem] bg-white/80 backdrop-blur-sm phx-submit-loading:flex">
                      <div class="flex items-center gap-3 rounded-full border border-pink-200 bg-white px-5 py-3 shadow-lg">
                        <span class="inline-block size-5 animate-spin rounded-full border-2 border-pink-200 border-t-pink-600" />
                        <div>
                          <p class="text-sm font-semibold text-slate-950">
                            {gettext("Unindo videos")}
                          </p>
                          <p class="text-xs text-slate-500">
                            {gettext("Isso pode levar alguns segundos.")}
                          </p>
                        </div>
                      </div>
                    </div>

                    <div class="rounded-[1.75rem] border border-dashed border-pink-200 bg-pink-50/60 p-5">
                      <div class="space-y-2">
                        <label
                          for="together-video-upload"
                          class="text-sm font-semibold text-slate-900"
                        >
                          {gettext("Videos de origem")}
                        </label>
                        <.live_file_input
                          upload={@uploads.video}
                          id="together-video-upload"
                          class="block w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700 shadow-sm transition file:mr-4 file:rounded-xl file:border-0 file:bg-slate-950 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-white hover:border-pink-300"
                        />
                        <p class="text-sm text-slate-500">
                          {gettext(
                            "Entradas aceitas: MP4, MOV, WEBM, MKV e AVI. Selecione ao menos dois arquivos."
                          )}
                        </p>
                      </div>

                      <div
                        id="together-videos-upload-list"
                        class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                      >
                        <div class="sticky top-0 z-10 rounded-2xl border border-pink-100 bg-pink-50/95 px-4 py-3 text-sm font-medium text-pink-900 backdrop-blur">
                          {upload_summary(@uploads.video.entries)}
                        </div>
                        <p class="px-4 text-xs font-medium uppercase tracking-[0.24em] text-pink-700">
                          {gettext(
                            "Reordene a fila com as setas para definir a sequencia final da faixa."
                          )}
                        </p>
                        <div
                          :for={
                            {entry, index} <-
                              Enum.with_index(ordered_entries(@uploads.video.entries, @video_order))
                          }
                          class="flex items-center gap-3 rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700"
                        >
                          <div class="min-w-0 flex-1 pr-4">
                            <p class="truncate font-medium">{entry.client_name}</p>
                            <div class="mt-2 h-2 rounded-full bg-slate-100">
                              <div
                                class="h-2 rounded-full bg-pink-400 transition-all"
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
                          <div class="flex items-center gap-2">
                            <button
                              :if={index > 0}
                              type="button"
                              phx-click="move-up"
                              phx-value-ref={entry.ref}
                              aria-label={gettext("Move %{filename} up", filename: entry.client_name)}
                              class="inline-flex size-8 shrink-0 items-center justify-center rounded-full border border-slate-200 text-sm font-bold text-slate-500 transition hover:border-pink-300 hover:bg-pink-50 hover:text-pink-700"
                            >
                              ↑
                            </button>
                            <button
                              :if={index < length(@uploads.video.entries) - 1}
                              type="button"
                              phx-click="move-down"
                              phx-value-ref={entry.ref}
                              aria-label={
                                gettext("Move %{filename} down", filename: entry.client_name)
                              }
                              class="inline-flex size-8 shrink-0 items-center justify-center rounded-full border border-slate-200 text-sm font-bold text-slate-500 transition hover:border-pink-300 hover:bg-pink-50 hover:text-pink-700"
                            >
                              ↓
                            </button>
                          </div>
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
                      id="together-videos-target-format"
                      label={gettext("Formato final")}
                      options={Enum.map(@formats, &{String.upcase(&1), &1})}
                      class="w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none transition focus:border-pink-400"
                    />

                    <button
                      type="submit"
                      id="together-videos-button"
                      phx-disable-with={gettext("Joining video files...")}
                      disabled={
                        !enough_completed_uploads?(@uploads.video.entries) ||
                          upload_in_progress?(@uploads.video.entries)
                      }
                      class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-pink-600 disabled:cursor-wait disabled:opacity-90"
                    >
                      <span class="inline-block size-4 animate-spin rounded-full border-2 border-white/30 border-t-white opacity-0 phx-submit-loading:opacity-100" />
                      <span>{gettext("Juntar videos")}</span>
                    </button>

                    <p
                      id="together-videos-status"
                      class="text-sm text-slate-500"
                    >
                      {upload_status_message(@uploads.video.entries)}
                    </p>
                  </.form>
                </div>

                <aside class="rounded-[2rem] border border-white/70 bg-slate-950 p-6 text-white shadow-[0_24px_60px_rgba(15,23,42,0.16)]">
                  <div :if={@result} class="space-y-4">
                    <p class="text-sm font-semibold uppercase tracking-[0.25em] text-pink-300">
                      {gettext("Arquivo final gerado")}
                    </p>
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="font-semibold">{@result.filename}</p>
                      <p class="mt-1 text-sm text-slate-300">
                        {gettext("%{count} video files joined as %{format}",
                          count: @result.source_count,
                          format: String.upcase(@result.target_format)
                        )}
                      </p>
                      <a
                        href={@result.download_path}
                        class="mt-3 inline-flex w-full items-center justify-center rounded-2xl bg-pink-400 px-4 py-3 text-sm font-semibold text-slate-950 transition hover:bg-pink-300"
                      >
                        {gettext("Baixar video final")}
                      </a>
                    </div>
                  </div>
                  <div :if={!@result} class="space-y-4">
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold uppercase tracking-[0.25em] text-pink-300">
                        {gettext("Como funciona")}
                      </p>
                      <p class="mt-3 text-sm text-slate-300">
                        {gettext(
                          "O Rapid Tools combina as faixas na ordem em que foram enviadas e exporta um unico arquivo final."
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
