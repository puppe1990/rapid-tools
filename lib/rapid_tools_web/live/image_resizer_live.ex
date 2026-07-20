defmodule RapidToolsWeb.ImageResizerLive do
  use RapidToolsWeb, :live_view

  alias Phoenix.LiveView.UploadConfig
  alias RapidTools.ConversionStore
  alias RapidTools.ImageResizer
  alias RapidTools.ZipArchive
  alias RapidToolsWeb.ToolNavigation

  @image_accept ~w(.jpg .jpeg .png .webp .heic .avif image/jpeg image/png image/webp image/heic image/avif)
  @max_image_upload_size 40_000_000
  @presets %{
    "instagram_post" => %{label: "Instagram Post", width: 1080, height: 1080},
    "instagram_story" => %{label: "Instagram Story", width: 1080, height: 1920},
    "youtube_thumb" => %{label: "YouTube Thumb", width: 1280, height: 720},
    "shopify_product" => %{label: "Shopify Product", width: 2048, height: 2048},
    "custom" => %{label: "Custom", width: 1600, height: 1600}
  }

  @impl true
  def mount(_params, session, socket) do
    locale =
      Locale.set_gettext_locale(
        session["locale"] || socket.assigns[:current_locale] || Locale.default_locale()
      )

    {:ok,
     socket
     |> assign(:current_locale, locale)
     |> assign(:formats, ImageResizer.supported_formats())
     |> assign(:tools, ToolNavigation.tools("image-resizer"))
     |> assign(:presets, @presets)
     |> assign(:results, [])
     |> assign(:batch_download_path, nil)
     |> assign(:upload_issue, nil)
     |> assign(:currently_resizing, nil)
     |> assign(:processing_queue, [])
     |> assign(:processing_total, 0)
     |> assign(:form, to_form(default_form_params(), as: :resize))
     |> assign(:my_path, "/image-resizer")
     |> allow_upload(:image,
       accept: @image_accept,
       max_entries: 10,
       max_file_size: @max_image_upload_size,
       auto_upload: true
     )}
  end

  @impl true
  def handle_event("validate", params, socket) do
    resize_params = Map.get(params, "resize", %{})
    changed_field = form_changed_field(params)

    {:noreply,
     socket
     |> assign(:form, to_form(apply_preset(resize_params, changed_field), as: :resize))
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
  def handle_event("resize", %{"resize" => resize_params}, socket) do
    if processing?(socket.assigns.currently_resizing) do
      {:noreply,
       put_flash(socket, :error, gettext("Aguarde o redimensionamento atual terminar."))}
    else
      # On submit, keep the dimensions shown in the form. If they no longer match the
      # selected named preset, treat the request as custom so 400x400 is not overwritten
      # by Instagram Post (1080x1080), etc.
      params = apply_preset(resize_params, nil)

      socket
      |> assign(:form, to_form(params, as: :resize))
      |> reconcile_image_uploads()
      |> continue_resize(params)
    end
  end

  defp continue_resize({:error, socket}, _params), do: {:noreply, socket}

  defp continue_resize({:ok, socket}, params) do
    case uploaded_entries(socket, :image) do
      {[], []} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Selecione ao menos uma imagem antes de redimensionar.")
         )}

      {_completed, [_ | _]} ->
        {:noreply,
         put_flash(socket, :error, gettext("Aguarde o upload terminar antes de redimensionar."))}

      _ ->
        {:noreply, start_resize(socket, params)}
    end
  end

  @impl true
  def handle_info({:begin_image_resize, staged_entries, params, results}, socket) do
    case staged_entries do
      [] ->
        {:noreply, finish_resize(socket, Enum.reverse(results))}

      [entry | rest] ->
        send(self(), {:run_image_resize, entry, rest, params, results})
        {:noreply, assign(socket, :currently_resizing, entry.client_name)}
    end
  end

  @impl true
  def handle_info({:run_image_resize, entry, rest, params, results}, socket) do
    result = resize_staged_entry(entry, params)
    send(self(), {:begin_image_resize, rest, params, [result | results]})
    {:noreply, socket}
  end

  defp start_resize(socket, params) do
    case stage_uploaded_entries(socket) do
      {:ok, []} ->
        put_flash(
          socket,
          :error,
          gettext("Selecione ao menos uma imagem antes de redimensionar.")
        )

      {:ok, staged_entries} ->
        send(self(), {:begin_image_resize, staged_entries, params, []})

        socket
        |> assign(:results, [])
        |> assign(:batch_download_path, nil)
        |> assign(:upload_issue, nil)
        |> assign(:processing_queue, Enum.map(staged_entries, & &1.client_name))
        |> assign(:processing_total, length(staged_entries))

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
      Logger.error("image resizer staging failed: #{inspect({kind, reason})}")
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

  defp resize_staged_entry(entry, %{
         "width" => width,
         "height" => height,
         "fit" => fit,
         "target_format" => target_format
       }) do
    case ImageResizer.resize(entry.source_path, width, height,
           fit: fit,
           target_format: target_format,
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
      {:error, {:resize_exception, Exception.message(error)}}
  end

  defp finish_resize(socket, results) do
    socket =
      socket
      |> assign(:currently_resizing, nil)
      |> assign(:processing_queue, [])
      |> assign(:processing_total, 0)

    case successful_batch_results(results) do
      {:ok, successful_results} ->
        build_batch_response(
          socket,
          successful_results,
          gettext("%{count} images resized.", count: length(successful_results)),
          gettext("As imagens foram geradas, mas o ZIP nao pode ser criado.")
        )

      :error ->
        put_flash(socket, :error, resize_error_message(results))
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
    gettext(
      "O upload desta imagem foi perdido antes do redimensionamento. Envie o arquivo novamente."
    )
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

  defp resize_error_message(results) do
    reasons = for {:error, reason} <- results, do: reason

    cond do
      :imagemagick_not_found in reasons ->
        gettext(
          "O redimensionador de imagens nao esta disponivel no servidor no momento. Tente novamente mais tarde."
        )

      Enum.any?(reasons, &match?({:resize_failed, _}, &1)) ->
        gettext(
          "Nao foi possivel redimensionar uma ou mais imagens. Verifique se os arquivos nao estao corrompidos e tente novamente."
        )

      true ->
        gettext("As imagens nao puderam ser redimensionadas.")
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

  defp default_form_params do
    %{
      "preset" => "instagram_post",
      "width" => "1080",
      "height" => "1080",
      "fit" => "contain",
      "target_format" => "original"
    }
  end

  defp form_changed_field(%{"_target" => ["resize", field | _]}) when is_binary(field), do: field
  defp form_changed_field(_), do: nil

  # Resolves form params so named presets fill dimensions, but typed width/height win.
  # changed_field is the form control that triggered phx-change (`"preset"`, `"width"`, ...),
  # or nil on submit.
  defp apply_preset(params, changed_field) do
    params = Map.merge(default_form_params(), params)
    preset = Map.get(params, "preset", "instagram_post")
    preset_config = Map.get(@presets, preset, @presets["custom"])

    cond do
      preset == "custom" ->
        params

      changed_field == "preset" ->
        params
        |> Map.put("width", Integer.to_string(preset_config.width))
        |> Map.put("height", Integer.to_string(preset_config.height))

      changed_field in ["width", "height"] ->
        Map.put(params, "preset", "custom")

      dimensions_match_preset?(params, preset_config) ->
        params
        |> Map.put("width", Integer.to_string(preset_config.width))
        |> Map.put("height", Integer.to_string(preset_config.height))

      true ->
        # Submit (or other field change) with dimensions that no longer match the named
        # preset: keep the typed size and mark as custom.
        Map.put(params, "preset", "custom")
    end
  end

  defp dimensions_match_preset?(params, %{width: width, height: height}) do
    parse_dimension(params["width"]) == width and parse_dimension(params["height"]) == height
  end

  defp parse_dimension(value) do
    case Integer.parse(to_string(value || "")) do
      {dimension, ""} -> dimension
      _ -> nil
    end
  end

  defp completed_upload_count(entries),
    do: Enum.count(entries, &(&1.progress == 100 && &1.valid?))

  defp upload_in_progress?(entries), do: Enum.any?(entries, &(&1.progress < 100 && &1.valid?))
  defp processing?(currently_resizing), do: currently_resizing != nil

  defp entries_with_errors?(entries) do
    Enum.any?(entries, &(not &1.valid?))
  end

  defp max_upload_mb, do: div(@max_image_upload_size, 1_000_000)

  defp upload_error_message(:too_large),
    do:
      gettext(
        "This file is too large. Maximum size is %{max_mb} MB.",
        max_mb: max_upload_mb()
      )

  defp upload_error_message(:not_accepted),
    do: gettext("Format not accepted. Upload JPG, JPEG, PNG, WEBP, HEIC, or AVIF.")

  defp upload_error_message(:too_many_files),
    do: gettext("You selected more files than allowed.")

  defp upload_error_message(:external_client_failure),
    do: gettext("The browser could not upload this file. Try again.")

  defp upload_error_message(_error), do: gettext("Could not upload this file.")

  defp upload_status_message(entries, currently_resizing, upload_issue) do
    cond do
      is_binary(upload_issue) ->
        upload_issue

      processing?(currently_resizing) ->
        gettext("Resizing %{filename}. Please wait a moment.", filename: currently_resizing)

      entries_with_errors?(entries) ->
        gettext("Some uploads failed. Remove the errored files or try smaller images.")

      entries == [] ->
        gettext("Selecione imagens para preparar tamanhos prontos para web e social.")

      upload_in_progress?(entries) ->
        gettext("Enviando imagens para o servidor. Aguarde todas chegarem a 100%.")

      true ->
        gettext("Uploads concluidos. Agora voce pode gerar as versoes redimensionadas.")
    end
  end

  defp upload_summary(entries, currently_resizing, processing_queue) do
    total = length(entries)
    completed = completed_upload_count(entries)
    errored = Enum.count(entries, &(not &1.valid?))

    cond do
      processing?(currently_resizing) ->
        gettext("Resizing image %{current} of %{total}",
          current: processing_position(currently_resizing, processing_queue),
          total: length(processing_queue)
        )

      total == 0 ->
        gettext("Nenhuma imagem selecionada ainda.")

      errored > 0 ->
        gettext("%{errored} of %{total} uploads need attention.",
          errored: errored,
          total: total
        )

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

  defp processing_position(currently_resizing, processing_queue) do
    case Enum.find_index(processing_queue, &(&1 == currently_resizing)) do
      nil -> 0
      index -> index + 1
    end
  end

  defp queue_item_status(name, currently_resizing, processing_queue) do
    current_index = Enum.find_index(processing_queue, &(&1 == currently_resizing))
    name_index = Enum.find_index(processing_queue, &(&1 == name))

    cond do
      name == currently_resizing ->
        :resizing

      is_integer(current_index) and is_integer(name_index) and name_index < current_index ->
        :done

      true ->
        :waiting
    end
  end

  defp can_submit?(entries, currently_resizing) do
    entries != [] and not upload_in_progress?(entries) and not entries_with_errors?(entries) and
      not processing?(currently_resizing)
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
      <section class="h-screen overflow-hidden bg-[radial-gradient(circle_at_top_left,_rgba(14,116,144,0.18),_transparent_30%),radial-gradient(circle_at_bottom_right,_rgba(6,182,212,0.14),_transparent_28%),linear-gradient(180deg,_rgba(240,249,255,1)_0%,_rgba(255,255,255,1)_52%,_rgba(236,254,255,1)_100%)]">
        <div class="mx-auto max-w-7xl h-full px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)] h-full">
            <.tool_sidebar
              tools={@tools}
              current_locale={@current_locale}
              redirect_to={@my_path}
              theme={%{sidebar_border_class: "border-cyan-100", accent_class: "text-cyan-700"}}
            />

            <div class="min-h-0 space-y-6 overflow-y-auto">
              <div class="space-y-4 px-2 py-2">
                <span class="inline-flex items-center rounded-full border border-cyan-200 bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-cyan-700">
                  {gettext("Image sizing")}
                </span>
                <h1 class="text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
                  {gettext("Resize images in bulk")}
                </h1>
                <p class="max-w-3xl text-base text-slate-600 sm:text-lg">
                  {gettext(
                    "Prepare product images, ad creatives, story assets, and thumbnails without editing one by one."
                  )}
                </p>
                <p class="text-sm text-slate-500">
                  {gettext(
                    "Escolha um preset pronto ou defina largura e altura customizadas para todo o lote."
                  )}
                </p>
              </div>

              <div class="grid gap-6 xl:grid-cols-[1.35fr_0.65fr]">
                <div class="relative rounded-[2rem] border border-white/70 bg-white p-6 shadow-[0_24px_60px_rgba(15,23,42,0.08)]">
                  <.form
                    for={@form}
                    id="image-resizer-form"
                    phx-change="validate"
                    phx-submit="resize"
                    class="space-y-6"
                  >
                    <div class="pointer-events-none absolute inset-0 z-10 hidden items-center justify-center rounded-[2rem] bg-white/80 backdrop-blur-sm phx-submit-loading:flex">
                      <div class="flex items-center gap-3 rounded-full border border-cyan-200 bg-white px-5 py-3 shadow-lg">
                        <span class="inline-block size-5 animate-spin rounded-full border-2 border-cyan-200 border-t-cyan-600" />
                        <div>
                          <p class="text-sm font-semibold text-slate-950">
                            {gettext("Resizing images")}
                          </p>
                          <p class="text-xs text-slate-500">
                            {gettext("This can take a few seconds.")}
                          </p>
                        </div>
                      </div>
                    </div>

                    <div
                      id="image-resizer-drop-zone"
                      phx-drop-target={@uploads.image.ref}
                      class="rounded-[1.75rem] border border-dashed border-cyan-200 bg-cyan-50/60 p-5"
                    >
                      <div class="space-y-2">
                        <label for="image-resizer-upload" class="text-sm font-semibold text-slate-900">
                          {gettext("Imagens de origem")}
                        </label>
                        <.live_file_input
                          upload={@uploads.image}
                          id="image-resizer-upload"
                          class="block w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700 shadow-sm transition file:mr-4 file:rounded-xl file:border-0 file:bg-slate-950 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-white hover:border-cyan-300"
                        />
                        <p class="text-sm text-slate-500">
                          {gettext(
                            "Entradas aceitas: JPG, JPEG, PNG, WEBP, HEIC e AVIF. Ate %{max_mb} MB por imagem.",
                            max_mb: max_upload_mb()
                          )}
                        </p>
                        <p
                          :if={@upload_issue}
                          class="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm font-medium text-amber-900"
                        >
                          {@upload_issue}
                        </p>
                      </div>

                      <div
                        :if={@currently_resizing}
                        id="image-resizer-currently-resizing"
                        class="mt-4 rounded-[1.5rem] border border-cyan-200 bg-cyan-100/80 p-4 text-cyan-950 shadow-[inset_0_1px_0_rgba(255,255,255,0.7)]"
                      >
                        <div class="flex items-start gap-3">
                          <span class="mt-1 inline-block size-4 animate-spin rounded-full border-2 border-cyan-300 border-t-cyan-700" />
                          <div class="min-w-0 flex-1">
                            <p class="text-xs font-semibold uppercase tracking-[0.28em] text-cyan-700">
                              {gettext("Resizing now")}
                            </p>
                            <p class="mt-2 truncate text-base font-semibold text-slate-950">
                              {@currently_resizing}
                            </p>
                            <p class="mt-2 text-sm text-cyan-800">
                              {gettext("Image %{current} of %{total}",
                                current: processing_position(@currently_resizing, @processing_queue),
                                total: @processing_total
                              )}
                            </p>
                          </div>
                        </div>
                      </div>

                      <div
                        :if={@processing_queue != []}
                        id="image-resizer-processing-queue"
                        class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                      >
                        <div class="sticky top-0 z-10 rounded-2xl border border-cyan-100 bg-cyan-50/95 px-4 py-3 text-sm font-medium text-cyan-900 backdrop-blur">
                          {upload_summary(
                            @uploads.image.entries,
                            @currently_resizing,
                            @processing_queue
                          )}
                        </div>
                        <div
                          :for={name <- @processing_queue}
                          class={[
                            "flex items-center gap-3 rounded-2xl border px-4 py-3 text-sm",
                            if(name == @currently_resizing,
                              do: "border-cyan-300 bg-cyan-50 text-cyan-950",
                              else: "border-slate-200 bg-white text-slate-700"
                            )
                          ]}
                        >
                          <div class="min-w-0 flex-1">
                            <p class="truncate font-medium">{name}</p>
                          </div>
                          <span class="text-xs uppercase tracking-[0.2em] text-slate-400">
                            <%= case queue_item_status(
                                  name,
                                  @currently_resizing,
                                  @processing_queue
                                ) do %>
                              <% :resizing -> %>
                                {gettext("resizing")}
                              <% :waiting -> %>
                                {gettext("waiting")}
                              <% :done -> %>
                                {gettext("done")}
                            <% end %>
                          </span>
                        </div>
                      </div>

                      <div
                        :if={@processing_queue == []}
                        id="image-resizer-upload-list"
                        class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                      >
                        <div class="sticky top-0 z-10 flex items-center justify-between gap-3 rounded-2xl border border-cyan-100 bg-cyan-50/95 px-4 py-3 text-sm font-medium text-cyan-900 backdrop-blur">
                          <span>
                            {upload_summary(
                              @uploads.image.entries,
                              @currently_resizing,
                              @processing_queue
                            )}
                          </span>
                          <button
                            :if={@uploads.image.entries != []}
                            type="button"
                            id="clear-upload-list"
                            phx-click="clear-uploads"
                            class="inline-flex shrink-0 items-center justify-center rounded-full border border-cyan-200 bg-white px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-cyan-700 transition hover:border-cyan-300 hover:bg-cyan-100"
                          >
                            {gettext("Limpar uploads")}
                          </button>
                        </div>
                        <div
                          :for={entry <- @uploads.image.entries}
                          class={[
                            "flex items-center gap-3 rounded-2xl border px-4 py-3 text-sm",
                            if(entry.valid?,
                              do: "border-slate-200 bg-white text-slate-700",
                              else: "border-rose-200 bg-rose-50 text-rose-900"
                            )
                          ]}
                        >
                          <div class="min-w-0 flex-1 pr-4">
                            <p class="truncate font-medium">{entry.client_name}</p>
                            <div class="mt-2 h-2 rounded-full bg-slate-100">
                              <div
                                class={[
                                  "h-2 rounded-full transition-all",
                                  if(entry.valid?, do: "bg-cyan-500", else: "bg-rose-400")
                                ]}
                                style={"width: #{if entry.valid?, do: entry.progress, else: 100}%"}
                              />
                            </div>
                            <p
                              :for={error <- upload_errors(@uploads.image, entry)}
                              class="mt-2 text-xs font-medium text-rose-600"
                            >
                              {upload_error_message(error)}
                            </p>
                          </div>
                          <span class="text-xs uppercase tracking-[0.2em] text-slate-400">
                            <%= cond do %>
                              <% not entry.valid? -> %>
                                {gettext("error")}
                              <% entry.progress == 100 -> %>
                                {gettext("pronto")}
                              <% true -> %>
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

                    <div class="grid gap-4 md:grid-cols-2">
                      <.input
                        field={@form[:preset]}
                        type="select"
                        label={gettext("Preset")}
                        options={Enum.map(@presets, fn {key, preset} -> {preset.label, key} end)}
                      />
                      <.input
                        field={@form[:target_format]}
                        type="select"
                        label={gettext("Formato de saida")}
                        options={Enum.map(@formats, fn format -> {String.upcase(format), format} end)}
                      />
                    </div>

                    <div class="grid gap-4 md:grid-cols-3">
                      <.input field={@form[:width]} type="number" label={gettext("Largura")} min="1" />
                      <.input field={@form[:height]} type="number" label={gettext("Altura")} min="1" />
                      <.input
                        field={@form[:fit]}
                        type="select"
                        label={gettext("Ajuste")}
                        options={[
                          {gettext("Contain"), "contain"},
                          {gettext("Cover"), "cover"},
                          {gettext("Stretch"), "stretch"}
                        ]}
                      />
                    </div>

                    <button
                      type="submit"
                      id="image-resize-button"
                      phx-disable-with={gettext("Generating images...")}
                      disabled={not can_submit?(@uploads.image.entries, @currently_resizing)}
                      class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-cyan-700 disabled:cursor-wait disabled:opacity-90"
                    >
                      <span>{gettext("Gerar imagens redimensionadas")}</span>
                    </button>

                    <p id="image-resizer-status" class="text-sm text-slate-500">
                      {upload_status_message(
                        @uploads.image.entries,
                        @currently_resizing,
                        @upload_issue
                      )}
                    </p>
                  </.form>
                </div>

                <aside class="rounded-[2rem] border border-white/70 bg-slate-950 p-6 text-white shadow-[0_24px_60px_rgba(15,23,42,0.16)]">
                  <div :if={@results != []} id="resized-results" class="space-y-4">
                    <p class="text-sm font-semibold uppercase tracking-[0.25em] text-cyan-300">
                      {gettext("%{count} images ready", count: length(@results))}
                    </p>
                    <a
                      :if={@batch_download_path}
                      href={@batch_download_path}
                      class="inline-flex w-full items-center justify-center rounded-2xl bg-cyan-400 px-4 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300"
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
                          {gettext("%{width} x %{height} in %{format}",
                            width: result.width,
                            height: result.height,
                            format: String.upcase(result.target_format)
                          )}
                        </p>
                        <a
                          href={result.download_path}
                          class="mt-3 inline-flex w-full items-center justify-center rounded-2xl border border-white/10 bg-white/10 px-4 py-3 text-sm font-semibold text-white transition hover:bg-white/20"
                        >
                          {gettext("Baixar imagem")}
                        </a>
                      </div>
                    </div>
                  </div>

                  <div :if={@results == []} class="space-y-4">
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold uppercase tracking-[0.25em] text-cyan-300">
                        {gettext("Presets prontos")}
                      </p>
                      <p class="mt-3 text-sm text-slate-300">
                        {gettext(
                          "Instagram Post, Instagram Story, YouTube Thumb e Shopify Product ja entram com dimensoes prontas."
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
