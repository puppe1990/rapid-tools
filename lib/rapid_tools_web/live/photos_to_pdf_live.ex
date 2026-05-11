defmodule RapidToolsWeb.PhotosToPdfLive do
  use RapidToolsWeb, :live_view

  alias RapidTools.ConversionStore
  alias RapidTools.PdfConverter
  alias RapidToolsWeb.ToolNavigation

  @image_accept ~w(.jpg .jpeg .png .webp .heic .avif)

  @impl true
  def mount(_params, session, socket) do
    locale =
      Locale.set_gettext_locale(
        session["locale"] || socket.assigns[:current_locale] || Locale.default_locale()
      )

    {:ok,
     socket
     |> assign(:current_locale, locale)
     |> assign(:tools, ToolNavigation.tools("photos-to-pdf"))
     |> assign(:result, nil)
     |> assign(:image_order, [])
     |> assign(:upload_input_version, 0)
     |> assign(:my_path, "/photos-to-pdf")
     |> allow_upload(:image, accept: @image_accept, max_entries: 100, auto_upload: true)}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, sync_image_order(socket, socket.assigns.uploads.image.entries)}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    entries = Enum.reject(socket.assigns.uploads.image.entries, &(&1.ref == ref))

    {:noreply,
     socket
     |> cancel_upload(:image, ref)
     |> assign(:image_order, remove_ref(socket.assigns.image_order, ref))
     |> sync_image_order(entries)}
  end

  @impl true
  def handle_event("move-up", %{"ref" => ref}, socket) do
    synced_order =
      synced_image_order(socket.assigns.image_order, socket.assigns.uploads.image.entries)

    {:noreply, assign(socket, :image_order, move_ref(synced_order, ref, -1))}
  end

  @impl true
  def handle_event("move-down", %{"ref" => ref}, socket) do
    synced_order =
      synced_image_order(socket.assigns.image_order, socket.assigns.uploads.image.entries)

    {:noreply, assign(socket, :image_order, move_ref(synced_order, ref, 1))}
  end

  @impl true
  def handle_event("build-pdf", _params, socket) do
    case uploaded_entries(socket, :image) do
      {[], []} ->
        {:noreply,
         put_flash(socket, :error, gettext("Select at least two photos to create the PDF."))}

      {_completed, [_ | _]} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Wait for uploads to finish before generating the PDF.")
         )}

      {completed, []} when length(completed) < 2 ->
        {:noreply,
         put_flash(socket, :error, gettext("Select at least two photos to create the PDF."))}

      _ ->
        {:noreply, build_pdf(socket)}
    end
  end

  defp build_pdf(socket) do
    output_dir =
      Path.join(
        System.tmp_dir!(),
        "rapid_tools_live/#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(output_dir)

    ordered_refs =
      synced_image_order(socket.assigns.image_order, socket.assigns.uploads.image.entries)

    source_paths =
      consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
        source_path = Path.join(output_dir, entry.client_name)
        File.cp!(path, source_path)
        {:ok, {entry.ref, source_path}}
      end)
      |> order_source_paths(ordered_refs)

    case PdfConverter.images_to_pdf(source_paths, output_dir: output_dir) do
      {:ok, result} ->
        store_entry = %{
          path: result.output_path,
          filename: result.filename,
          media_type: result.media_type
        }

        {:ok, id} = ConversionStore.put(store_entry)

        pdf_result =
          Map.merge(result, %{
            download_path: ~p"/downloads/#{id}",
            source_count: length(source_paths)
          })

        socket
        |> assign(:result, pdf_result)
        |> assign(:image_order, [])
        |> assign(:upload_input_version, socket.assigns.upload_input_version + 1)
        |> put_flash(
          :info,
          gettext("%{count} photos combined into a PDF successfully.",
            count: length(source_paths)
          )
        )

      {:error, :source_files_not_found} ->
        put_flash(socket, :error, gettext("Select at least two photos to create the PDF."))

      {:error, _reason} ->
        put_flash(socket, :error, gettext("The photos could not be combined into a PDF."))
    end
  end

  defp completed_upload_count(entries), do: Enum.count(entries, &(&1.progress == 100))
  defp upload_in_progress?(entries), do: Enum.any?(entries, &(&1.progress < 100))
  defp enough_completed_uploads?(entries), do: completed_upload_count(entries) >= 2

  defp upload_status_message(entries) do
    cond do
      entries == [] ->
        gettext("Select at least two photos to enable PDF generation.")

      upload_in_progress?(entries) ->
        gettext("Uploading photos to the server. Wait until all of them reach 100%.")

      !enough_completed_uploads?(entries) ->
        gettext("Add at least one more photo before starting the PDF build.")

      true ->
        gettext("Uploads completed. You can now generate the PDF.")
    end
  end

  defp upload_summary(entries) do
    total = length(entries)
    completed = completed_upload_count(entries)

    cond do
      total == 0 ->
        gettext("No photo selected yet.")

      upload_in_progress?(entries) ->
        gettext(
          "%{total} photos in queue. %{completed}/%{total} finished so far, the rest are still uploading.",
          total: total,
          completed: completed
        )

      true ->
        gettext("%{count} photos selected. Reorder them below before generating the PDF.",
          count: total
        )
    end
  end

  defp sync_image_order(socket, entries) do
    assign(socket, :image_order, synced_image_order(socket.assigns.image_order, entries))
  end

  defp synced_image_order(current_order, entries) do
    entry_refs = Enum.map(entries, & &1.ref)
    kept_refs = Enum.filter(current_order, &(&1 in entry_refs))
    new_refs = Enum.reject(entry_refs, &(&1 in kept_refs))
    kept_refs ++ new_refs
  end

  defp ordered_entries(entries, image_order) do
    order = synced_image_order(image_order, entries)
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
      main_class="px-0 pb-8 pt-0 sm:px-0 lg:px-0"
      content_class="w-full"
      show_header={false}
    >
      <section class="min-h-screen bg-[radial-gradient(circle_at_top_left,_rgba(14,165,233,0.16),_transparent_28%),radial-gradient(circle_at_bottom_right,_rgba(8,145,178,0.16),_transparent_30%),linear-gradient(180deg,_rgba(240,249,255,1)_0%,_rgba(255,255,255,1)_54%,_rgba(236,254,255,1)_100%)]">
        <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)]">
            <.tool_sidebar
              tools={@tools}
              current_locale={@current_locale}
              redirect_to={@my_path}
              theme={%{sidebar_border_class: "border-sky-100", accent_class: "text-sky-700"}}
            />

            <div class="space-y-6">
              <div class="space-y-4 px-2 py-2">
                <span class="inline-flex items-center rounded-full border border-sky-200 bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-sky-700">
                  {gettext("Photo layout")}
                </span>
                <h1 class="text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
                  {gettext("Photos to PDF")}
                </h1>
                <p class="max-w-3xl text-base text-slate-600 sm:text-lg">
                  {gettext(
                    "Upload multiple photos, rearrange the page order and generate a single PDF ready to download."
                  )}
                </p>
                <p class="text-sm text-slate-500">
                  {gettext(
                    "Ideal for portfolios, receipts, scans, product photos and visual sequences that should become one document."
                  )}
                </p>
              </div>

              <div id="photos-to-pdf-panel" class="grid gap-6 xl:grid-cols-[1.35fr_0.65fr]">
                <div class="relative rounded-[2rem] border border-white/70 bg-white p-6 shadow-[0_24px_60px_rgba(15,23,42,0.08)]">
                  <.form
                    for={%{}}
                    id="photos-to-pdf-form"
                    phx-change="validate"
                    phx-submit="build-pdf"
                    class="space-y-6"
                  >
                    <div class="pointer-events-none absolute inset-0 z-10 hidden items-center justify-center rounded-[2rem] bg-white/80 backdrop-blur-sm phx-submit-loading:flex">
                      <div class="flex items-center gap-3 rounded-full border border-sky-200 bg-white px-5 py-3 shadow-lg">
                        <span class="inline-block size-5 animate-spin rounded-full border-2 border-sky-200 border-t-sky-600" />
                        <div>
                          <p class="text-sm font-semibold text-slate-950">
                            {gettext("Generating PDF")}
                          </p>
                          <p class="text-xs text-slate-500">
                            {gettext("Isso pode levar alguns segundos.")}
                          </p>
                        </div>
                      </div>
                    </div>

                    <div class="rounded-[1.75rem] border border-dashed border-sky-200 bg-sky-50/60 p-5">
                      <div class="space-y-2">
                        <label
                          for={"photos-to-pdf-upload-#{@upload_input_version}"}
                          class="text-sm font-semibold text-slate-900"
                        >
                          {gettext("Source photos")}
                        </label>
                        <.live_file_input
                          upload={@uploads.image}
                          id={"photos-to-pdf-upload-#{@upload_input_version}"}
                          class="block w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700 shadow-sm transition file:mr-4 file:rounded-xl file:border-0 file:bg-slate-950 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-white hover:border-sky-300"
                        />
                        <p class="text-sm text-slate-500">
                          {gettext(
                            "Accepted inputs: JPG, PNG, WEBP, HEIC and AVIF. Upload at least two photos."
                          )}
                        </p>
                      </div>

                      <div
                        id="photos-to-pdf-upload-list"
                        class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                      >
                        <div class="sticky top-0 z-10 rounded-2xl border border-sky-100 bg-sky-50/95 px-4 py-3 text-sm font-medium text-sky-900 backdrop-blur">
                          {upload_summary(@uploads.image.entries)}
                        </div>
                        <p class="px-4 text-xs font-medium uppercase tracking-[0.24em] text-sky-700">
                          {gettext("Reorder the queue with the arrows to define the PDF page order.")}
                        </p>
                        <div
                          :for={
                            {entry, index} <-
                              Enum.with_index(ordered_entries(@uploads.image.entries, @image_order))
                          }
                          class="flex items-center gap-3 rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700"
                        >
                          <div class="min-w-0 flex-1 pr-4">
                            <p class="truncate font-medium">{entry.client_name}</p>
                            <div class="mt-2 h-2 rounded-full bg-slate-100">
                              <div
                                class="h-2 rounded-full bg-sky-500 transition-all"
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
                              class="inline-flex size-8 shrink-0 items-center justify-center rounded-full border border-slate-200 text-sm font-bold text-slate-500 transition hover:border-sky-300 hover:bg-sky-50 hover:text-sky-700"
                            >
                              ↑
                            </button>
                            <button
                              :if={index < length(@uploads.image.entries) - 1}
                              type="button"
                              phx-click="move-down"
                              phx-value-ref={entry.ref}
                              aria-label={
                                gettext("Move %{filename} down", filename: entry.client_name)
                              }
                              class="inline-flex size-8 shrink-0 items-center justify-center rounded-full border border-slate-200 text-sm font-bold text-slate-500 transition hover:border-sky-300 hover:bg-sky-50 hover:text-sky-700"
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

                    <button
                      type="submit"
                      id="photos-to-pdf-button"
                      phx-disable-with={gettext("Generating PDF...")}
                      disabled={
                        !enough_completed_uploads?(@uploads.image.entries) ||
                          upload_in_progress?(@uploads.image.entries)
                      }
                      class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-sky-700 disabled:cursor-wait disabled:opacity-90"
                    >
                      <span class="inline-block size-4 animate-spin rounded-full border-2 border-white/30 border-t-white opacity-0 phx-submit-loading:opacity-100" />
                      <span>{gettext("Create PDF from photos")}</span>
                    </button>

                    <p id="photos-to-pdf-status" class="text-sm text-slate-500">
                      {upload_status_message(@uploads.image.entries)}
                    </p>
                  </.form>
                </div>

                <aside class="rounded-[2rem] border border-white/70 bg-slate-950 p-6 text-white shadow-[0_24px_60px_rgba(15,23,42,0.16)]">
                  <div :if={@result} class="space-y-4">
                    <p class="text-sm font-semibold uppercase tracking-[0.25em] text-sky-300">
                      {gettext("Generated PDF")}
                    </p>
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="font-semibold">{@result.filename}</p>
                      <p class="mt-1 text-sm text-slate-300">
                        {gettext("%{count} photos turned into a single PDF",
                          count: @result.source_count
                        )}
                      </p>
                      <a
                        href={@result.download_path}
                        class="mt-3 inline-flex w-full items-center justify-center rounded-2xl bg-sky-300 px-4 py-3 text-sm font-semibold text-slate-950 transition hover:bg-sky-200"
                      >
                        {gettext("Download PDF")}
                      </a>
                    </div>
                  </div>
                  <div :if={!@result} class="space-y-4">
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold uppercase tracking-[0.25em] text-sky-300">
                        {gettext("How it works")}
                      </p>
                      <p class="mt-3 text-sm text-slate-300">
                        {gettext(
                          "Rapid Tools respects the order shown in the queue and turns each photo into a page in the final PDF."
                        )}
                      </p>
                    </div>
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold text-white">{gettext("Best for")}</p>
                      <p class="mt-2 text-sm text-slate-300">
                        {gettext(
                          "Quick catalogs, visual dossiers, scanned documents, receipts and image sequences you need to share as a single file."
                        )}
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
