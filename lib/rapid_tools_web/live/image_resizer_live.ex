defmodule RapidToolsWeb.ImageResizerLive do
  use RapidToolsWeb, :live_view

  alias RapidTools.ConversionStore
  alias RapidTools.ImageResizer
  alias RapidTools.ZipArchive
  alias RapidToolsWeb.ToolNavigation

  @image_accept ~w(.jpg .jpeg .png .webp .heic .avif)
  @presets %{
    "instagram_post" => %{label: "Instagram Post", width: 1080, height: 1080},
    "instagram_story" => %{label: "Instagram Story", width: 1080, height: 1920},
    "youtube_thumb" => %{label: "YouTube Thumb", width: 1280, height: 720},
    "shopify_product" => %{label: "Shopify Product", width: 2048, height: 2048},
    "custom" => %{label: "Custom", width: 1600, height: 1600}
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:formats, ImageResizer.supported_formats())
     |> assign(:tools, ToolNavigation.tools("image-resizer"))
     |> assign(:presets, @presets)
     |> assign(:results, [])
     |> assign(:batch_download_path, nil)
     |> assign(:form, to_form(default_form_params(), as: :resize))
     |> assign(:current_locale, socket.assigns[:current_locale] || "en")
     |> assign(:my_path, "/image-resizer")
     |> allow_upload(:image, accept: @image_accept, max_entries: 10, auto_upload: true)}
  end

  @impl true
  def handle_event("validate", %{"resize" => resize_params}, socket) do
    {:noreply, assign(socket, :form, to_form(apply_preset(resize_params), as: :resize))}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  @impl true
  def handle_event("resize", %{"resize" => resize_params}, socket) do
    params = apply_preset(resize_params)

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
        {:noreply, resize_uploads(assign(socket, :form, to_form(params, as: :resize)), params)}
    end
  end

  defp resize_uploads(socket, %{
         "width" => width,
         "height" => height,
         "fit" => fit,
         "target_format" => target_format
       }) do
    results =
      consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
        output_dir =
          Path.join(System.tmp_dir!(), "rapid_tools_live/#{System.unique_integer([:positive])}")

        File.mkdir_p!(output_dir)

        source_path = Path.join(output_dir, entry.client_name)
        File.cp!(path, source_path)

        case ImageResizer.resize(source_path, width, height,
               fit: fit,
               target_format: target_format,
               output_dir: output_dir
             ) do
          {:ok, result} ->
            store_entry = %{
              path: result.output_path,
              filename: result.filename,
              media_type: result.media_type
            }

            {:ok, id} = ConversionStore.put(store_entry)
            {:ok, {:ok, Map.put(result, :download_path, ~p"/downloads/#{id}")}}

          {:error, reason} ->
            {:ok, {:error, reason}}
        end
      end)

    case successful_batch_results(results) do
      {:ok, successful_results} ->
        build_batch_response(
          socket,
          successful_results,
          "#{length(successful_results)} imagens redimensionadas.",
          gettext("As imagens foram geradas, mas o ZIP nao pode ser criado.")
        )

      :error ->
        put_flash(socket, :error, gettext("As imagens nao puderam ser redimensionadas."))
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

  defp default_form_params do
    %{
      "preset" => "instagram_post",
      "width" => "1080",
      "height" => "1080",
      "fit" => "contain",
      "target_format" => "original"
    }
  end

  defp apply_preset(params) do
    preset = Map.get(params, "preset", "instagram_post")
    preset_config = Map.get(@presets, preset, @presets["custom"])

    if preset == "custom" do
      Map.merge(default_form_params(), params)
    else
      params
      |> Map.merge(default_form_params())
      |> Map.put("width", Integer.to_string(preset_config.width))
      |> Map.put("height", Integer.to_string(preset_config.height))
    end
  end

  defp completed_upload_count(entries), do: Enum.count(entries, &(&1.progress == 100))
  defp upload_in_progress?(entries), do: Enum.any?(entries, &(&1.progress < 100))

  defp upload_status_message(entries) do
    cond do
      entries == [] ->
        gettext("Selecione imagens para preparar tamanhos prontos para web e social.")

      upload_in_progress?(entries) ->
        gettext("Enviando imagens para o servidor. Aguarde todas chegarem a 100%.")

      true ->
        gettext("Uploads concluidos. Agora voce pode gerar as versoes redimensionadas.")
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
      <section class="min-h-screen bg-[radial-gradient(circle_at_top_left,_rgba(14,116,144,0.18),_transparent_30%),radial-gradient(circle_at_bottom_right,_rgba(6,182,212,0.14),_transparent_28%),linear-gradient(180deg,_rgba(240,249,255,1)_0%,_rgba(255,255,255,1)_52%,_rgba(236,254,255,1)_100%)]">
        <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)]">
            <.tool_sidebar
              tools={@tools}
              current_locale={@current_locale}
              redirect_to={@my_path}
              theme={%{sidebar_border_class: "border-cyan-100", accent_class: "text-cyan-700"}}
            />

            <div class="space-y-6">
              <div class="space-y-4 px-2 py-2">
                <span class="inline-flex items-center rounded-full border border-cyan-200 bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-cyan-700">
                  Image sizing
                </span>
                <h1 class="text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
                  Resize images in bulk
                </h1>
                <p class="max-w-3xl text-base text-slate-600 sm:text-lg">
                  Prepare product images, ad creatives, story assets, and thumbnails without editing one by one.
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
                    <div class="rounded-[1.75rem] border border-dashed border-cyan-200 bg-cyan-50/60 p-5">
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
                          {gettext("Entradas aceitas: JPG, JPEG, PNG, WEBP, HEIC e AVIF.")}
                        </p>
                      </div>

                      <div
                        id="image-resizer-upload-list"
                        class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                      >
                        <div class="sticky top-0 z-10 rounded-2xl border border-cyan-100 bg-cyan-50/95 px-4 py-3 text-sm font-medium text-cyan-900 backdrop-blur">
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
                                class="h-2 rounded-full bg-cyan-500 transition-all"
                                style={"width: #{entry.progress}%"}
                              />
                            </div>
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
                            aria-label={"Remover #{entry.client_name}"}
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
                        options={[{"Contain", "contain"}, {"Cover", "cover"}, {"Stretch", "stretch"}]}
                      />
                    </div>

                    <button
                      type="submit"
                      id="image-resize-button"
                      phx-disable-with="Gerando imagens..."
                      disabled={
                        @uploads.image.entries == [] || upload_in_progress?(@uploads.image.entries)
                      }
                      class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-cyan-700 disabled:cursor-wait disabled:opacity-90"
                    >
                      <span>{gettext("Gerar imagens redimensionadas")}</span>
                    </button>

                    <p class="text-sm text-slate-500">
                      {upload_status_message(@uploads.image.entries)}
                    </p>
                  </.form>
                </div>

                <aside class="rounded-[2rem] border border-white/70 bg-slate-950 p-6 text-white shadow-[0_24px_60px_rgba(15,23,42,0.16)]">
                  <div :if={@results != []} class="space-y-4">
                    <p class="text-sm font-semibold uppercase tracking-[0.25em] text-cyan-300">
                      {length(@results)} imagens prontas
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
                          {result.width} x {result.height} em {String.upcase(result.target_format)}
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
