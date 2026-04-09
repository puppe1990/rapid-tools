defmodule RapidToolsWeb.ImageConverterLive do
  use RapidToolsWeb, :live_view

  alias RapidTools.ConversionStore
  alias RapidTools.ImageConverter
  alias RapidTools.ZipArchive
  alias RapidToolsWeb.ToolNavigation

  @image_accept ~w(.jpg .jpeg .png .webp .heic .avif)

  @impl true
  def mount(_params, _session, socket) do
    form =
      to_form(
        %{"target_format" => default_target_format()},
        as: :conversion
      )

    {:ok,
     socket
     |> assign(:formats, ImageConverter.supported_formats())
     |> assign(:tools, ToolNavigation.tools("image"))
     |> assign(:form, form)
     |> assign(:results, [])
     |> assign(:batch_download_path, nil)
     |> assign(:current_locale, socket.assigns[:current_locale] || "en")
     |> assign(:my_path, "/")
     |> allow_upload(:image, accept: @image_accept, max_entries: 10, auto_upload: true)}
  end

  @impl true
  def handle_event("validate", %{"conversion" => conversion_params}, socket) do
    {:noreply, assign(socket, :form, to_form(conversion_params, as: :conversion))}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  @impl true
  def handle_event("clear-uploads", _params, socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.image.entries, socket, fn entry, acc ->
        cancel_upload(acc, :image, entry.ref)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear-converted-results", _params, socket) do
    {:noreply,
     socket
     |> assign(:results, [])
     |> assign(:batch_download_path, nil)
     |> clear_flash(:info)
     |> clear_flash(:error)}
  end

  @impl true
  def handle_event("convert", %{"conversion" => %{"target_format" => target_format}}, socket) do
    case uploaded_entries(socket, :image) do
      {[], []} ->
        {:noreply,
         put_flash(socket, :error, gettext("Selecione ao menos uma imagem antes de converter."))}

      {_completed, [_ | _]} ->
        {:noreply,
         put_flash(socket, :error, gettext("Aguarde o upload terminar antes de converter."))}

      _ ->
        {:noreply, convert_upload(socket, target_format)}
    end
  end

  defp convert_upload(socket, target_format) do
    results =
      consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
        output_dir =
          Path.join(
            System.tmp_dir!(),
            "rapid_tools_live/#{System.unique_integer([:positive])}"
          )

        File.mkdir_p!(output_dir)

        source_path = Path.join(output_dir, entry.client_name)
        File.cp!(path, source_path)

        case ImageConverter.convert(source_path, target_format, output_dir: output_dir) do
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
          "#{length(successful_results)} imagens convertidas.",
          gettext("As imagens foram convertidas, mas o pacote ZIP nao pode ser gerado.")
        )

      :error ->
        put_flash(socket, :error, gettext("A imagem nao pode ser convertida."))
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

  defp default_target_format, do: "png"

  defp completed_upload_count(entries) do
    Enum.count(entries, &(&1.progress == 100))
  end

  defp upload_in_progress?(entries) do
    Enum.any?(entries, &(&1.progress < 100))
  end

  defp upload_status_message(entries) do
    cond do
      entries == [] ->
        gettext("Selecione uma ou mais imagens para habilitar a conversao.")

      upload_in_progress?(entries) ->
        gettext("Enviando imagens para o servidor. Aguarde todas chegarem a 100%.")

      true ->
        gettext("Uploads concluidos. Agora voce pode converter em lote.")
    end
  end

  defp upload_summary(entries) do
    total = length(entries)
    completed = completed_upload_count(entries)

    cond do
      total == 0 ->
        gettext("Nenhuma imagem selecionada ainda.")

      upload_in_progress?(entries) ->
        "#{total} imagens na fila. #{completed}/#{total} concluidas ate agora, o restante ainda esta enviando."

      true ->
        "#{total} imagens selecionadas. Todas aparecem nesta caixa com scroll."
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
      <section class="min-h-screen bg-[radial-gradient(circle_at_top_left,_rgba(255,118,35,0.16),_transparent_28%),radial-gradient(circle_at_bottom_right,_rgba(251,191,36,0.14),_transparent_26%),linear-gradient(180deg,_rgba(250,245,239,1)_0%,_rgba(255,255,255,1)_50%,_rgba(248,244,238,1)_100%)]">
        <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)]">
            <.tool_sidebar
              tools={@tools}
              current_locale={@current_locale}
              redirect_to={@my_path}
              theme={%{sidebar_border_class: "border-orange-100", accent_class: "text-orange-600"}}
            />

            <div class="space-y-6">
              <div class="space-y-4 px-2 py-2">
                <span class="inline-flex items-center rounded-full border border-orange-200 bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-orange-700">
                  Image workflow
                </span>
                <h1 class="text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
                  Image Converter
                </h1>
                <p class="max-w-3xl text-base text-slate-600 sm:text-lg">
                  {gettext(
                    "Converta imagens para PNG, JPG, WEBP, HEIC e AVIF com downloads individuais ou em lote."
                  )}
                </p>
                <p class="text-sm text-slate-500">
                  {gettext(
                    "Ideal para exportar assets para web, social, aplicativos e bibliotecas de design."
                  )}
                </p>
              </div>

              <div id="converter-panel" class="grid gap-6 xl:grid-cols-[1.35fr_0.65fr]">
                <div class="relative rounded-[2rem] border border-white/70 bg-white p-6 shadow-[0_24px_60px_rgba(15,23,42,0.08)]">
                  <.form
                    for={@form}
                    id="converter-form"
                    phx-change="validate"
                    phx-submit="convert"
                    class="space-y-6"
                  >
                    <div class="pointer-events-none absolute inset-0 z-10 hidden items-center justify-center rounded-[2rem] bg-white/80 backdrop-blur-sm phx-submit-loading:flex">
                      <div class="flex items-center gap-3 rounded-full border border-orange-200 bg-white px-5 py-3 shadow-lg">
                        <span class="inline-block size-5 animate-spin rounded-full border-2 border-orange-200 border-t-orange-600" />
                        <div>
                          <p class="text-sm font-semibold text-slate-950">
                            {gettext("Convertendo imagens")}
                          </p>
                          <p class="text-xs text-slate-500">
                            {gettext("Isso pode levar alguns segundos.")}
                          </p>
                        </div>
                      </div>
                    </div>

                    <div class="rounded-[1.75rem] border border-dashed border-orange-200 bg-orange-50/60 p-5">
                      <div class="space-y-2">
                        <label for="image-upload" class="text-sm font-semibold text-slate-900">
                          {gettext("Imagens de origem")}
                        </label>
                        <.live_file_input
                          upload={@uploads.image}
                          id="image-upload"
                          class="block w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700 shadow-sm transition file:mr-4 file:rounded-xl file:border-0 file:bg-slate-950 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-white hover:border-orange-300"
                        />
                        <p class="text-sm text-slate-500">
                          {gettext("Entradas aceitas: JPG, JPEG, PNG, WEBP, HEIC e AVIF.")}
                        </p>
                      </div>

                      <div
                        id="image-upload-list"
                        class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                      >
                        <div class="sticky top-0 z-10 flex items-center justify-between gap-3 rounded-2xl border border-orange-100 bg-orange-50/95 px-4 py-3 text-sm font-medium text-orange-900 backdrop-blur">
                          <span>{upload_summary(@uploads.image.entries)}</span>
                          <button
                            :if={@uploads.image.entries != []}
                            type="button"
                            id="clear-upload-list"
                            phx-click="clear-uploads"
                            class="inline-flex shrink-0 items-center justify-center rounded-full border border-orange-200 bg-white px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-orange-700 transition hover:border-orange-300 hover:bg-orange-100"
                          >
                            {gettext("Limpar uploads")}
                          </button>
                        </div>
                        <div
                          :for={entry <- @uploads.image.entries}
                          class="flex items-center gap-3 rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700"
                        >
                          <div class="min-w-0 flex-1 pr-4">
                            <p class="truncate font-medium">{entry.client_name}</p>
                            <div class="mt-2 h-2 rounded-full bg-slate-100">
                              <div
                                class="h-2 rounded-full bg-orange-400 transition-all"
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
                      id="image-target-format"
                      label={gettext("Formato de destino")}
                      options={Enum.map(@formats, &{String.upcase(&1), &1})}
                      class="w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none transition focus:border-orange-400"
                    />

                    <button
                      type="submit"
                      id="image-convert-button"
                      phx-disable-with="Convertendo imagens..."
                      disabled={
                        @uploads.image.entries == [] || upload_in_progress?(@uploads.image.entries)
                      }
                      class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-orange-600 disabled:cursor-wait disabled:opacity-90"
                    >
                      <span class="inline-block size-4 animate-spin rounded-full border-2 border-white/30 border-t-white opacity-0 phx-submit-loading:opacity-100" />
                      <span>{gettext("Converter imagens")}</span>
                    </button>

                    <p id="image-converter-status" class="text-sm text-slate-500">
                      {upload_status_message(@uploads.image.entries)}
                    </p>
                  </.form>
                </div>

                <aside class="rounded-[2rem] border border-white/70 bg-slate-950 p-6 text-white shadow-[0_24px_60px_rgba(15,23,42,0.16)]">
                  <div :if={@results != []} id="converted-results" class="space-y-4">
                    <div class="flex items-center justify-between gap-3">
                      <p class="text-sm font-semibold uppercase tracking-[0.25em] text-orange-300">
                        {length(@results)} imagens convertidas
                      </p>
                      <button
                        type="button"
                        id="clear-converted-results"
                        phx-click="clear-converted-results"
                        class="inline-flex shrink-0 items-center justify-center rounded-full border border-white/15 bg-white/10 px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-white transition hover:bg-white/20"
                      >
                        {gettext("Limpar convertidas")}
                      </button>
                    </div>
                    <a
                      :if={@batch_download_path}
                      href={@batch_download_path}
                      class="inline-flex w-full items-center justify-center rounded-2xl bg-orange-400 px-4 py-3 text-sm font-semibold text-slate-950 transition hover:bg-orange-300"
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
                          {gettext("Baixar imagem convertida")}
                        </a>
                      </div>
                    </div>
                  </div>
                  <div :if={@results == []} class="space-y-4">
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold uppercase tracking-[0.25em] text-orange-300">
                        {gettext("Lote pronto para exportar")}
                      </p>
                      <p class="mt-3 text-sm text-slate-300">
                        {gettext(
                          "Envie varias imagens, escolha o formato final e baixe cada arquivo convertido ou um ZIP com tudo junto."
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
