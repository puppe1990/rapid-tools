defmodule RapidToolsWeb.ImageConverterLive do
  use RapidToolsWeb, :live_view

  alias Phoenix.LiveView.UploadConfig
  alias RapidTools.ConversionStore
  alias RapidTools.ImageConverter
  alias RapidTools.ZipArchive
  alias RapidToolsWeb.ToolNavigation

  @image_accept ~w(.jpg .jpeg .png .webp .heic .avif .enc)
  @max_image_upload_size 40_000_000

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
     |> assign(:formats, ImageConverter.supported_formats())
     |> assign(:tools, ToolNavigation.tools("image"))
     |> assign(:form, form)
     |> assign(:results, [])
     |> assign(:batch_download_path, nil)
     |> assign(:upload_issue, nil)
     |> assign(:currently_converting, nil)
     |> assign(:processing_queue, [])
     |> assign(:processing_total, 0)
     |> assign(:my_path, "/")
     |> allow_upload(:image,
       accept: @image_accept,
       max_entries: 10,
       max_file_size: @max_image_upload_size,
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
    {:noreply, socket |> cancel_upload(:image, ref) |> maybe_clear_upload_issue()}
  end

  @impl true
  def handle_event("clear-uploads", _params, socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.image.entries, socket, fn entry, acc ->
        cancel_upload(acc, :image, entry.ref)
      end)

    {:noreply, maybe_clear_upload_issue(socket)}
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
    if processing?(socket.assigns.currently_converting) do
      {:noreply, put_flash(socket, :error, gettext("Aguarde a conversao atual terminar."))}
    else
      socket
      |> reconcile_image_uploads()
      |> continue_convert(target_format)
    end
  end

  defp continue_convert({:error, socket}, _target_format), do: {:noreply, socket}

  defp continue_convert({:ok, socket}, target_format) do
    case uploaded_entries(socket, :image) do
      {[], []} ->
        {:noreply,
         put_flash(socket, :error, gettext("Selecione ao menos uma imagem antes de converter."))}

      {_completed, [_ | _]} ->
        {:noreply,
         put_flash(socket, :error, gettext("Aguarde o upload terminar antes de converter."))}

      _ ->
        {:noreply, start_conversion(socket, target_format)}
    end
  end

  @impl true
  def handle_info(
        {:begin_image_conversion, staged_entries, target_format, results},
        socket
      ) do
    case staged_entries do
      [] ->
        {:noreply, finish_conversion(socket, Enum.reverse(results))}

      [entry | rest] ->
        send(self(), {:run_image_conversion, entry, rest, target_format, results})

        {:noreply,
         socket
         |> assign(:currently_converting, entry.client_name)
         |> assign(:processing_queue, Enum.map([entry | rest], & &1.client_name))}
    end
  end

  @impl true
  def handle_info(
        {:run_image_conversion, entry, rest, target_format, results},
        socket
      ) do
    result = convert_staged_entry(entry, target_format)
    send(self(), {:begin_image_conversion, rest, target_format, [result | results]})
    {:noreply, socket}
  end

  defp start_conversion(socket, target_format) do
    case stage_uploaded_entries(socket) do
      {:ok, []} ->
        put_flash(socket, :error, gettext("Selecione ao menos uma imagem antes de converter."))

      {:ok, staged_entries} ->
        send(self(), {:begin_image_conversion, staged_entries, target_format, []})

        socket
        |> assign(:results, [])
        |> assign(:batch_download_path, nil)
        |> assign(:upload_issue, nil)
        |> assign(:processing_total, length(staged_entries))
        |> assign(:form, to_form(%{"target_format" => target_format}, as: :conversion))

      {:error, socket} ->
        socket
    end
  end

  defp stage_uploaded_entries(socket) do
    staged_entries =
      consume_uploaded_entries(socket, :image, fn meta, entry ->
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
      Logger.error("image converter staging failed: #{inspect({kind, reason})}")
      {:error, staging_error_socket(socket)}
  end

  defp stage_single_upload(%{path: path}, entry) do
    output_dir =
      Path.join(
        System.tmp_dir!(),
        "rapid_tools_live/#{System.unique_integer([:positive])}"
      )

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

  defp convert_staged_entry(entry, target_format) do
    case ImageConverter.convert(entry.source_path, target_format, output_dir: entry.output_dir) do
      {:ok, result} ->
        store_entry = %{
          path: result.output_path,
          filename: result.filename,
          media_type: result.media_type
        }

        case ConversionStore.put(store_entry) do
          {:ok, id} ->
            {:ok,
             %{
               download_path: ~p"/downloads/#{id}",
               output_path: result.output_path,
               media_type: result.media_type,
               filename: result.filename,
               target_format: result.target_format
             }}

          other ->
            {:error, {:store_failed, other}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      {:error, {:conversion_exception, Exception.message(error)}}
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
          gettext("%{count} images converted.", count: length(successful_results)),
          gettext("As imagens foram convertidas, mas o pacote ZIP nao pode ser gerado.")
        )

      :error ->
        put_flash(socket, :error, conversion_error_message(results))
    end
  end

  defp reconcile_image_uploads(socket) do
    stale_refs = stale_image_upload_refs(socket)

    if stale_refs == [] do
      {:ok, socket}
    else
      {:error,
       socket
       |> assign(:upload_issue, lost_upload_message())
       |> put_flash(:error, lost_upload_message())}
    end
  end

  defp stale_image_upload_refs(socket) do
    conf = socket.assigns.uploads.image

    for entry <- conf.entries,
        pid = UploadConfig.entry_pid(conf, entry),
        is_pid(pid),
        not Process.alive?(pid),
        do: entry.ref
  end

  defp maybe_clear_upload_issue(socket) do
    if socket.assigns.uploads.image.entries == [] do
      assign(socket, :upload_issue, nil)
    else
      socket
    end
  end

  defp lost_upload_message do
    gettext("O upload desta imagem foi perdido antes da conversao. Envie o arquivo novamente.")
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

  defp conversion_error_message(results) do
    reasons = for {:error, reason} <- results, do: reason

    cond do
      :imagemagick_not_found in reasons ->
        gettext(
          "O conversor de imagens nao esta disponivel no servidor no momento. Tente novamente mais tarde."
        )

      Enum.any?(reasons, &match?({:unsupported_target_format, _}, &1)) ->
        gettext("Formato de destino nao suportado. Escolha PNG, JPG, WEBP, HEIC, AVIF ou ENC.")

      Enum.any?(reasons, &match?({:conversion_failed, _}, &1)) ->
        gettext(
          "Nao foi possivel converter uma ou mais imagens. Verifique se os arquivos nao estao corrompidos e tente outro formato."
        )

      true ->
        gettext("A imagem nao pode ser convertida.")
    end
  end

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
      {:error, _reason} ->
        socket
        |> assign(:results, successful_results)
        |> assign(:batch_download_path, nil)
        |> put_flash(:error, zip_error_message)

      _other ->
        socket
        |> assign(:results, successful_results)
        |> assign(:batch_download_path, nil)
        |> put_flash(:info, success_message)
    end
  end

  defp safe_client_name(name) when is_binary(name) do
    name
    |> Path.basename()
    |> String.replace(~r/[\x00-\x1F\x7F]/, "_")
    |> case do
      "" -> "image"
      safe -> safe
    end
  end

  defp safe_client_name(_), do: "image"

  defp default_target_format, do: "png"

  defp completed_upload_count(entries) do
    Enum.count(entries, &(&1.progress == 100))
  end

  defp upload_in_progress?(entries) do
    Enum.any?(entries, &(&1.progress < 100))
  end

  defp processing?(currently_converting), do: currently_converting != nil

  defp upload_status_message(entries, currently_converting, upload_issue) do
    cond do
      is_binary(upload_issue) ->
        upload_issue

      processing?(currently_converting) ->
        gettext("Conversao em andamento. Acompanhe qual arquivo esta sendo processado agora.")

      entries == [] ->
        gettext("Selecione uma ou mais imagens para habilitar a conversao.")

      upload_in_progress?(entries) ->
        gettext("Enviando imagens para o servidor. Aguarde todas chegarem a 100%.")

      true ->
        gettext("Uploads concluidos. Agora voce pode converter em lote.")
    end
  end

  defp upload_summary(entries, currently_converting) do
    total = length(entries)
    completed = completed_upload_count(entries)

    cond do
      processing?(currently_converting) ->
        gettext(
          "Fila enviada para conversao. A imagem atual aparece com loader e o restante fica na sequencia."
        )

      total == 0 ->
        gettext("Nenhuma imagem selecionada ainda.")

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

  defp processing_position(assigns) do
    queue_count = length(assigns.processing_queue)

    if assigns.processing_total > 0 and queue_count > 0 do
      assigns.processing_total - queue_count + 1
    else
      0
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
      <section class="h-screen overflow-hidden bg-[radial-gradient(circle_at_top_left,_rgba(255,118,35,0.16),_transparent_28%),radial-gradient(circle_at_bottom_right,_rgba(251,191,36,0.14),_transparent_26%),linear-gradient(180deg,_rgba(250,245,239,1)_0%,_rgba(255,255,255,1)_50%,_rgba(248,244,238,1)_100%)]">
        <div class="mx-auto max-w-7xl h-full px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)] h-full">
            <.tool_sidebar
              tools={@tools}
              current_locale={@current_locale}
              redirect_to={@my_path}
              theme={%{sidebar_border_class: "border-orange-100", accent_class: "text-orange-600"}}
            />

            <div class="space-y-6 overflow-y-auto">
              <div class="space-y-4 px-2 py-2">
                <span class="inline-flex items-center rounded-full border border-orange-200 bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-orange-700">
                  {gettext("Image workflow")}
                </span>
                <h1 class="text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
                  {gettext("Image Converter")}
                </h1>
                <p class="max-w-3xl text-base text-slate-600 sm:text-lg">
                  {gettext(
                    "Converta imagens para PNG, JPG, WEBP, HEIC, AVIF e ENC com downloads individuais ou em lote."
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
                    <div class={[
                      "pointer-events-none absolute inset-0 z-10 items-center justify-center rounded-[2rem] bg-white/80 backdrop-blur-sm",
                      if(processing?(@currently_converting),
                        do: "flex",
                        else: "hidden phx-submit-loading:flex"
                      )
                    ]}>
                      <div class="flex items-center gap-3 rounded-full border border-orange-200 bg-white px-5 py-3 shadow-lg">
                        <span class="inline-block size-5 animate-spin rounded-full border-2 border-orange-200 border-t-orange-600" />
                        <div>
                          <p class="text-sm font-semibold text-slate-950">
                            <%= if @currently_converting do %>
                              {gettext("Convertendo")}: {@currently_converting}
                            <% else %>
                              {gettext("Convertendo imagens")}
                            <% end %>
                          </p>
                          <p class="text-xs text-slate-500">
                            <%= if @currently_converting && @processing_total > 0 do %>
                              {gettext("%{current} of %{total}",
                                current: processing_position(assigns),
                                total: @processing_total
                              )}
                            <% else %>
                              {gettext("Isso pode levar alguns segundos.")}
                            <% end %>
                          </p>
                        </div>
                      </div>
                    </div>

                    <div
                      id="image-drop-zone"
                      phx-drop-target={@uploads.image.ref}
                      class="rounded-[1.75rem] border border-dashed border-orange-200 bg-orange-50/60 p-5"
                    >
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
                          {gettext("Entradas aceitas: JPG, JPEG, PNG, WEBP, HEIC, AVIF e ENC.")}
                        </p>
                      </div>

                      <div
                        id="image-upload-list"
                        class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                      >
                        <div class="sticky top-0 z-10 flex items-center justify-between gap-3 rounded-2xl border border-orange-100 bg-orange-50/95 px-4 py-3 text-sm font-medium text-orange-900 backdrop-blur">
                          <span>{upload_summary(@uploads.image.entries, @currently_converting)}</span>
                          <button
                            :if={
                              @uploads.image.entries != [] and not processing?(@currently_converting)
                            }
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
                            disabled={processing?(@currently_converting)}
                            aria-label={gettext("Remove %{filename}", filename: entry.client_name)}
                            class="inline-flex size-8 shrink-0 items-center justify-center rounded-full border border-slate-200 text-sm font-bold text-slate-500 transition hover:border-red-200 hover:bg-red-50 hover:text-red-600 disabled:cursor-not-allowed disabled:opacity-40"
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
                      phx-disable-with={gettext("Converting images...")}
                      disabled={
                        @uploads.image.entries == [] || upload_in_progress?(@uploads.image.entries) ||
                          processing?(@currently_converting)
                      }
                      class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-orange-600 disabled:cursor-wait disabled:opacity-90"
                    >
                      <span class="inline-block size-4 animate-spin rounded-full border-2 border-white/30 border-t-white opacity-0 phx-submit-loading:opacity-100" />
                      <span>{gettext("Converter imagens")}</span>
                    </button>

                    <p id="image-converter-status" class="text-sm text-slate-500">
                      {upload_status_message(
                        @uploads.image.entries,
                        @currently_converting,
                        @upload_issue
                      )}
                    </p>
                  </.form>
                </div>

                <aside class="rounded-[2rem] border border-white/70 bg-slate-950 p-6 text-white shadow-[0_24px_60px_rgba(15,23,42,0.16)]">
                  <div :if={@results != []} id="converted-results" class="space-y-4">
                    <div class="flex items-center justify-between gap-3">
                      <p class="text-sm font-semibold uppercase tracking-[0.25em] text-orange-300">
                        {gettext("%{count} images converted", count: length(@results))}
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
