defmodule RapidToolsWeb.QrReaderLive do
  use RapidToolsWeb, :live_view

  alias RapidTools.QrReader
  alias RapidToolsWeb.ToolNavigation

  @image_accept ~w(.jpg .jpeg .png .webp)

  @impl true
  def mount(_params, session, socket) do
    locale =
      Locale.set_gettext_locale(
        session["locale"] || socket.assigns[:current_locale] || Locale.default_locale()
      )

    {:ok,
     socket
     |> assign(:current_locale, locale)
     |> assign(:tools, ToolNavigation.tools("qr-reader"))
     |> assign(:mode, "upload")
     |> assign(:decoded_text, nil)
     |> assign(:decoded_source, nil)
     |> assign(:zbar_available?, QrReader.available?())
     |> assign(:my_path, "/qr-reader")
     |> allow_upload(:image, accept: @image_accept, max_entries: 1, auto_upload: true)}
  end

  @impl true
  def handle_event("set-mode", %{"mode" => mode}, socket) when mode in ["upload", "camera"] do
    {:noreply, assign(socket, :mode, mode)}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  @impl true
  def handle_event("read", _params, socket) do
    cond do
      not socket.assigns.zbar_available? ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Upload decoding is unavailable. Install zbar on the server.")
         )}

      socket.assigns.mode != "upload" ->
        {:noreply, socket}

      true ->
        case uploaded_entries(socket, :image) do
          {[], []} ->
            {:noreply,
             put_flash(socket, :error, gettext("Select an image before reading the QR code."))}

          {_completed, [_ | _]} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Wait for the upload to finish before reading the QR code.")
             )}

          _ ->
            {:noreply, read_upload(socket)}
        end
    end
  end

  @impl true
  def handle_event("scan-result", %{"text" => text}, socket) do
    text = String.trim(text)

    if text == "" do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:decoded_text, text)
       |> assign(:decoded_source, "camera")}
    end
  end

  @impl true
  def handle_event("clear-result", _params, socket) do
    {:noreply,
     socket
     |> assign(:decoded_text, nil)
     |> assign(:decoded_source, nil)}
  end

  defp read_upload(socket) do
    result =
      consume_uploaded_entries(socket, :image, fn %{path: path}, _entry ->
        {:ok, QrReader.read(path)}
      end)

    case result do
      [{:ok, text}] when is_binary(text) ->
        assign(socket, decoded_text: text, decoded_source: "upload")

      [{:error, :no_qr_found}] ->
        put_flash(socket, :error, gettext("No QR code was found in the uploaded image."))

      [{:error, :zbar_unavailable}] ->
        put_flash(
          socket,
          :error,
          gettext("Upload decoding is unavailable. Install zbar on the server.")
        )

      _ ->
        put_flash(socket, :error, gettext("The QR code could not be read."))
    end
  end

  defp completed_upload_count(entries), do: Enum.count(entries, &(&1.progress == 100))

  defp upload_in_progress?(entries), do: Enum.any?(entries, &(&1.progress < 100))

  defp upload_ready?(entries) do
    completed_upload_count(entries) == 1 and not upload_in_progress?(entries)
  end

  defp upload_status_message(entries) do
    cond do
      entries == [] ->
        gettext("Select an image that contains a QR code.")

      upload_in_progress?(entries) ->
        gettext("Uploading the image. Wait until it reaches 100%.")

      true ->
        gettext("Upload complete. You can read the QR code now.")
    end
  end

  defp upload_summary(entries) do
    cond do
      entries == [] ->
        gettext("No image selected yet.")

      upload_in_progress?(entries) ->
        gettext("1 image in queue. Still uploading.")

      true ->
        gettext("1 image selected and ready to decode.")
    end
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
      <section class="h-screen overflow-hidden bg-[radial-gradient(circle_at_top_left,_rgba(132,204,22,0.18),_transparent_30%),radial-gradient(circle_at_bottom_right,_rgba(101,163,13,0.14),_transparent_28%),linear-gradient(180deg,_rgba(247,254,231,1)_0%,_rgba(255,255,255,1)_52%,_rgba(236,252,203,1)_100%)]">
        <div class="mx-auto max-w-7xl h-full px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)] h-full">
            <.tool_sidebar
              tools={@tools}
              current_locale={@current_locale}
              redirect_to={@my_path}
              theme={%{sidebar_border_class: "border-lime-100", accent_class: "text-lime-700"}}
            />

            <div class="min-h-0 space-y-6 overflow-y-auto">
              <div class="space-y-4 px-2 py-2">
                <span class="inline-flex items-center rounded-full border border-lime-200 bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-lime-700">
                  {gettext("QR scanning")}
                </span>
                <h1 class="text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
                  {gettext("Read QR codes from images or your camera")}
                </h1>
                <p class="max-w-3xl text-base text-slate-600 sm:text-lg">
                  {gettext("Upload a photo with a QR code or scan one live with your device camera.")}
                </p>
              </div>

              <div id="qr-reader-panel" class="grid gap-6 xl:grid-cols-[1.35fr_0.65fr]">
                <div class="relative rounded-[2rem] border border-white/70 bg-white p-6 shadow-[0_24px_60px_rgba(15,23,42,0.08)]">
                  <div class="mb-6 flex flex-wrap gap-2">
                    <button
                      type="button"
                      id="qr-reader-mode-upload"
                      phx-click="set-mode"
                      phx-value-mode="upload"
                      class={[
                        "rounded-full px-4 py-2 text-sm font-semibold transition",
                        @mode == "upload" &&
                          "bg-lime-500 text-white shadow-sm",
                        @mode != "upload" &&
                          "border border-slate-200 bg-white text-slate-700 hover:border-lime-200 hover:bg-lime-50"
                      ]}
                    >
                      {gettext("Upload image")}
                    </button>
                    <button
                      type="button"
                      id="qr-reader-mode-camera"
                      phx-click="set-mode"
                      phx-value-mode="camera"
                      class={[
                        "rounded-full px-4 py-2 text-sm font-semibold transition",
                        @mode == "camera" &&
                          "bg-lime-500 text-white shadow-sm",
                        @mode != "camera" &&
                          "border border-slate-200 bg-white text-slate-700 hover:border-lime-200 hover:bg-lime-50"
                      ]}
                    >
                      {gettext("Use camera")}
                    </button>
                  </div>

                  <.form for={%{}} id="qr-reader-form" phx-submit="read" class="space-y-6">
                    <div
                      id="qr-reader-upload-panel"
                      class={["space-y-6", @mode != "upload" && "hidden"]}
                    >
                      <div
                        :if={not @zbar_available?}
                        class="rounded-[1.5rem] border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900"
                      >
                        <p class="font-semibold">{gettext("Upload decoding is unavailable")}</p>
                        <p class="mt-2">
                          {gettext(
                            "Install zbar on the server to decode QR codes from uploaded images."
                          )}
                        </p>
                      </div>

                      <div
                        id="qr-reader-drop-zone"
                        phx-drop-target={@uploads.image.ref}
                        class="rounded-[1.75rem] border border-dashed border-lime-200 bg-lime-50/60 p-5"
                      >
                        <div class="space-y-2">
                          <label for="qr-reader-upload" class="text-sm font-semibold text-slate-900">
                            {gettext("Source image")}
                          </label>
                          <.live_file_input
                            upload={@uploads.image}
                            id="qr-reader-upload"
                            class="block w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700 shadow-sm transition file:mr-4 file:rounded-xl file:border-0 file:bg-slate-950 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-white hover:border-lime-300"
                          />
                          <p class="text-sm text-slate-500">
                            {gettext("Accepted inputs: JPG, JPEG, PNG and WEBP.")}
                          </p>
                        </div>

                        <div
                          id="qr-reader-upload-list"
                          class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                        >
                          <div class="sticky top-0 z-10 rounded-2xl border border-lime-100 bg-lime-50/95 px-4 py-3 text-sm font-medium text-lime-900 backdrop-blur">
                            {upload_summary(@uploads.image.entries)}
                          </div>
                          <div
                            :for={entry <- @uploads.image.entries}
                            class="flex items-center gap-3 rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700"
                          >
                            <div class="min-w-0 flex-1 pr-4">
                              <p class="truncate font-medium">{entry.client_name}</p>
                              <div class="mt-2 h-2 rounded-full bg-slate-100">
                                <div
                                  class="h-2 rounded-full bg-lime-500 transition-all"
                                  style={"width: #{entry.progress}%"}
                                />
                              </div>
                            </div>
                            <span class="text-xs uppercase tracking-[0.2em] text-slate-400">
                              {if entry.progress == 100,
                                do: gettext("ready"),
                                else: "#{entry.progress}%"}
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

                      <button
                        type="submit"
                        id="qr-reader-read-button"
                        phx-disable-with={gettext("Reading QR code...")}
                        disabled={not upload_ready?(@uploads.image.entries) or not @zbar_available?}
                        class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-lime-600 disabled:cursor-not-allowed disabled:opacity-60"
                      >
                        <span class="inline-block size-4 animate-spin rounded-full border-2 border-white/30 border-t-white opacity-0 phx-submit-loading:opacity-100" />
                        <span>{gettext("Read QR code")}</span>
                      </button>

                      <p id="qr-reader-status" class="text-sm text-slate-500">
                        {upload_status_message(@uploads.image.entries)}
                      </p>
                    </div>

                    <div
                      id="qr-reader-camera-panel"
                      class={["space-y-4", @mode != "camera" && "hidden"]}
                    >
                      <p class="text-sm text-slate-600">
                        {gettext(
                          "Allow camera access when prompted, then point the lens at a QR code."
                        )}
                      </p>
                      <div
                        id="qr-reader-camera"
                        phx-hook="QrScanner"
                        phx-update="ignore"
                        data-active={@mode == "camera"}
                        class="overflow-hidden rounded-[1.75rem] border border-lime-200 bg-slate-950"
                      />
                    </div>
                  </.form>
                </div>

                <aside
                  id="qr-reader-result"
                  class="rounded-[2rem] border border-white/70 bg-slate-950 p-6 text-white shadow-[0_24px_60px_rgba(15,23,42,0.16)]"
                >
                  <div :if={@decoded_text} class="space-y-4">
                    <p class="text-sm font-semibold uppercase tracking-[0.25em] text-lime-300">
                      {gettext("Decoded content")}
                    </p>
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-lime-200">
                        {gettext("Source")}: {@decoded_source}
                      </p>
                      <p class="mt-3 break-all font-mono text-sm text-white">{@decoded_text}</p>
                      <p id="qr-reader-copy-hint" class="mt-3 text-sm text-slate-300">
                        {gettext("Select the decoded text and copy it to your clipboard.")}
                      </p>
                      <button
                        type="button"
                        phx-click="clear-result"
                        class="mt-4 inline-flex w-full items-center justify-center rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm font-semibold text-white transition hover:bg-white/10"
                      >
                        {gettext("Clear result")}
                      </button>
                    </div>
                  </div>
                  <div :if={!@decoded_text} class="space-y-4">
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold uppercase tracking-[0.25em] text-lime-300">
                        {gettext("No QR code read yet")}
                      </p>
                      <p class="mt-3 text-sm text-slate-300">
                        {gettext(
                          "Upload an image or switch to camera mode to decode the first QR code."
                        )}
                      </p>
                    </div>
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold text-white">{gettext("How it works")}</p>
                      <p class="mt-2 text-sm text-slate-300">
                        {gettext(
                          "Uploaded images are decoded on the server with zbar. Camera scans run locally in your browser."
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
