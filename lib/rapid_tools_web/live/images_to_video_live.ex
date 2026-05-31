defmodule RapidToolsWeb.ImagesToVideoLive do
  use RapidToolsWeb, :live_view

  alias RapidTools.ConversionStore
  alias RapidTools.ImagesToVideoConverter
  alias RapidToolsWeb.ToolNavigation

  @image_accept ~w(.png .jpg .jpeg .webp)

  @impl true
  def mount(_params, session, socket) do
    locale =
      Locale.set_gettext_locale(
        session["locale"] || socket.assigns[:current_locale] || Locale.default_locale()
      )

    form =
      to_form(
        %{"target_format" => default_target_format(), "interval" => "2"},
        as: :conversion
      )

    {:ok,
     socket
     |> assign(:current_locale, locale)
     |> assign(:formats, ImagesToVideoConverter.supported_formats())
     |> assign(:tools, ToolNavigation.tools("images-to-video"))
     |> assign(:form, form)
     |> assign(:result, nil)
     |> assign(:image_order, [])
     |> assign(:my_path, "/images-to-video")
     |> allow_upload(:image, accept: @image_accept, max_entries: 100, auto_upload: true)}
  end

  @impl true
  def handle_event("validate", %{"conversion" => conversion_params}, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(conversion_params, as: :conversion))
     |> sync_image_order(socket.assigns.uploads.image.entries)}
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
  def handle_event("convert", %{"conversion" => conversion_params}, socket) do
    target_format = conversion_params["target_format"] || default_target_format()
    interval = parse_interval(conversion_params["interval"])

    case uploaded_entries(socket, :image) do
      {[], []} ->
        {:noreply,
         put_flash(socket, :error, gettext("Select at least one image to create a video."))}

      {_completed, [_ | _]} ->
        {:noreply,
         put_flash(socket, :error, gettext("Wait for the upload to finish before converting."))}

      {completed, []} ->
        {:noreply, convert_uploads(socket, completed, target_format, interval)}
    end
  end

  defp convert_uploads(socket, _completed_entries, target_format, interval) do
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

    case ImagesToVideoConverter.convert(source_paths, target_format,
           output_dir: output_dir,
           interval: interval
         ) do
      {:ok, result} ->
        store_entry = %{
          path: result.output_path,
          filename: result.filename,
          media_type: result.media_type
        }

        {:ok, id} = ConversionStore.put(store_entry)

        result =
          Map.merge(result, %{
            download_path: ~p"/downloads/#{id}",
            source_count: length(source_paths),
            interval: interval
          })

        socket
        |> assign(:result, result)
        |> put_flash(
          :info,
          gettext("%{count} images converted successfully.", count: length(source_paths))
        )

      {:error, :not_enough_source_files} ->
        put_flash(socket, :error, gettext("Select at least one image to create a video."))

      {:error, _reason} ->
        put_flash(socket, :error, gettext("The images could not be converted."))
    end
  end

  defp parse_interval(interval) when is_binary(interval) do
    case Integer.parse(interval) do
      {n, _} when n > 0 -> n
      _ -> 2
    end
  end

  defp parse_interval(_), do: 2

  defp default_target_format, do: "mp4"

  defp completed_upload_count(entries) do
    Enum.count(entries, &(&1.progress == 100))
  end

  defp upload_in_progress?(entries) do
    Enum.any?(entries, &(&1.progress < 100))
  end

  defp enough_completed_uploads?(entries) do
    completed_upload_count(entries) >= 1
  end

  defp upload_status_message(entries) do
    cond do
      entries == [] ->
        gettext("Select at least one image to enable conversion.")

      upload_in_progress?(entries) ->
        gettext("Uploading files to the server. Wait for all to reach 100%.")

      true ->
        gettext("Uploads complete. You can now create the video.")
    end
  end

  defp upload_summary(entries) do
    total = length(entries)
    completed = completed_upload_count(entries)

    cond do
      total == 0 ->
        gettext("No images selected yet.")

      upload_in_progress?(entries) ->
        gettext(
          "%{total} images in queue. %{completed}/%{total} finished so far, the rest are still uploading.",
          total: total,
          completed: completed
        )

      true ->
        gettext("%{count} images selected. All of them appear in this scrollable list.",
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

  defp download_label("mp4"), do: gettext("Download MP4")
  defp download_label("gif"), do: gettext("Download GIF")
  defp download_label(_), do: gettext("Download")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      main_class="px-0 pb-0 pt-0 sm:px-0 lg:px-0"
      content_class="w-full"
      show_header={false}
    >
      <section class="h-screen overflow-hidden bg-[radial-gradient(circle_at_top_left,_rgba(45,212,191,0.16),_transparent_28%),radial-gradient(circle_at_bottom_right,_rgba(20,184,166,0.14),_transparent_26%),linear-gradient(180deg,_rgba(248,246,242,1)_0%,_rgba(255,255,255,1)_52%,_rgba(241,248,247,1)_100%)]">
        <div class="mx-auto max-w-7xl h-full px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)] h-full">
            <.tool_sidebar
              tools={@tools}
              current_locale={@current_locale}
              redirect_to={@my_path}
              theme={%{sidebar_border_class: "border-teal-100", accent_class: "text-teal-600"}}
            />

            <div class="space-y-6 overflow-y-auto">
              <div class="space-y-4 px-2 py-2">
                <span class="inline-flex items-center rounded-full border border-teal-200 bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-teal-700">
                  {gettext("Image sequence")}
                </span>
                <h1 class="text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
                  {gettext("Images to Video")}
                </h1>
                <p class="max-w-3xl text-base text-slate-600 sm:text-lg">
                  {gettext("Turn your photos into a video or animated GIF.")}
                </p>
                <p class="text-sm text-slate-500">
                  {gettext(
                    "Upload images, set the duration between frames, choose the output format and download the result."
                  )}
                </p>
              </div>

              <div id="images-to-video-panel" class="grid gap-6 xl:grid-cols-[1.35fr_0.65fr]">
                <div class="relative rounded-[2rem] border border-white/70 bg-white p-6 shadow-[0_24px_60px_rgba(15,23,42,0.08)]">
                  <.form
                    for={@form}
                    id="images-to-video-form"
                    phx-change="validate"
                    phx-submit="convert"
                    class="space-y-6"
                  >
                    <div class="pointer-events-none absolute inset-0 z-10 hidden items-center justify-center rounded-[2rem] bg-white/80 backdrop-blur-sm phx-submit-loading:flex">
                      <div class="flex items-center gap-3 rounded-full border border-teal-200 bg-white px-5 py-3 shadow-lg">
                        <span class="inline-block size-5 animate-spin rounded-full border-2 border-teal-200 border-t-teal-600" />
                        <div>
                          <p class="text-sm font-semibold text-slate-950">
                            {gettext("Creating video")}
                          </p>
                          <p class="text-xs text-slate-500">
                            {gettext("Isso pode levar alguns segundos.")}
                          </p>
                        </div>
                      </div>
                    </div>

                    <div
                      id="images-to-video-drop-zone"
                      phx-drop-target={@uploads.image.ref}
                      class="rounded-[1.75rem] border border-dashed border-teal-200 bg-teal-50/60 p-5"
                    >
                      <div class="space-y-2">
                        <label
                          for="images-to-video-upload"
                          class="text-sm font-semibold text-slate-900"
                        >
                          {gettext("Source images")}
                        </label>
                        <.live_file_input
                          upload={@uploads.image}
                          id="images-to-video-upload"
                          class="block w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700 shadow-sm transition file:mr-4 file:rounded-xl file:border-0 file:bg-slate-950 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-white hover:border-teal-300"
                        />
                        <p class="text-sm text-slate-500">
                          {gettext("Accepted: PNG, JPG, JPEG and WEBP. Select at least one image.")}
                        </p>
                      </div>

                      <div
                        id="images-to-video-upload-list"
                        class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                      >
                        <div class="sticky top-0 z-10 rounded-2xl border border-teal-100 bg-teal-50/95 px-4 py-3 text-sm font-medium text-teal-900 backdrop-blur">
                          {upload_summary(@uploads.image.entries)}
                        </div>
                        <p class="px-4 text-xs font-medium uppercase tracking-[0.24em] text-teal-700">
                          {gettext(
                            "Reorder the queue with the arrows to define the final sequence of frames."
                          )}
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
                                class="h-2 rounded-full bg-teal-400 transition-all"
                                style={"width: #{entry.progress}%"}
                              />
                            </div>
                          </div>
                          <span class="text-xs uppercase tracking-[0.2em] text-slate-400">
                            <%= if entry.progress == 100 do %>
                              {gettext("ready")}
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
                              class="inline-flex size-8 shrink-0 items-center justify-center rounded-full border border-slate-200 text-sm font-bold text-slate-500 transition hover:border-teal-300 hover:bg-teal-50 hover:text-teal-700"
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
                              class="inline-flex size-8 shrink-0 items-center justify-center rounded-full border border-slate-200 text-sm font-bold text-slate-500 transition hover:border-teal-300 hover:bg-teal-50 hover:text-teal-700"
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

                    <div class="grid gap-4 sm:grid-cols-2">
                      <.input
                        field={@form[:target_format]}
                        type="select"
                        id="images-to-video-target-format"
                        label={gettext("Output format")}
                        options={Enum.map(@formats, &{String.upcase(&1), &1})}
                        class="w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none transition focus:border-teal-400"
                      />

                      <.input
                        field={@form[:interval]}
                        type="number"
                        id="images-to-video-interval"
                        label={gettext("Seconds between frames")}
                        min="1"
                        max="60"
                        class="w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none transition focus:border-teal-400"
                      />
                    </div>

                    <button
                      type="submit"
                      id="images-to-video-button"
                      phx-disable-with={gettext("Creating video...")}
                      disabled={
                        !enough_completed_uploads?(@uploads.image.entries) ||
                          upload_in_progress?(@uploads.image.entries)
                      }
                      class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-teal-600 disabled:cursor-wait disabled:opacity-90"
                    >
                      <span class="inline-block size-4 animate-spin rounded-full border-2 border-white/30 border-t-white opacity-0 phx-submit-loading:opacity-100" />
                      <span>{gettext("Create video")}</span>
                    </button>

                    <p
                      id="images-to-video-status"
                      class="text-sm text-slate-500"
                    >
                      {upload_status_message(@uploads.image.entries)}
                    </p>
                  </.form>
                </div>

                <aside class="rounded-[2rem] border border-white/70 bg-slate-950 p-6 text-white shadow-[0_24px_60px_rgba(15,23,42,0.16)]">
                  <div :if={@result} id="images-to-video-result" class="space-y-4">
                    <p class="text-sm font-semibold uppercase tracking-[0.25em] text-teal-300">
                      {gettext("Generated file")}
                    </p>
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="font-semibold">{@result.filename}</p>
                      <p class="mt-1 text-sm text-slate-300">
                        {gettext(
                          "%{count} images joined as %{format} with %{interval}s between frames",
                          count: @result.source_count,
                          format: String.upcase(@result.target_format),
                          interval: @result.interval
                        )}
                      </p>
                      <a
                        href={@result.download_path}
                        class="mt-3 inline-flex w-full items-center justify-center rounded-2xl bg-teal-400 px-4 py-3 text-sm font-semibold text-slate-950 transition hover:bg-teal-300"
                        download
                      >
                        {download_label(@result.target_format)}
                      </a>
                    </div>
                  </div>
                  <div :if={!@result} class="space-y-4">
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold uppercase tracking-[0.25em] text-teal-300">
                        {gettext("How it works")}
                      </p>
                      <p class="mt-3 text-sm text-slate-300">
                        {gettext(
                          "Rapid Tools arranges the images in the order they were uploaded and exports a single MP4 or GIF file with the chosen interval between frames."
                        )}
                      </p>
                    </div>
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold text-white">{gettext("Supported outputs")}</p>
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
