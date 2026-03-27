defmodule RapidToolsWeb.PdfConverterLive do
  use RapidToolsWeb, :live_view

  alias RapidTools.ConversionStore
  alias RapidTools.PdfConverter
  alias RapidTools.ZipArchive
  alias RapidToolsWeb.ToolNavigation

  @document_accept ~w(.pdf .jpg .jpeg .png .webp)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:tools, ToolNavigation.tools("pdf-converter"))
     |> assign(:results, [])
     |> assign(:batch_download_path, nil)
     |> assign(:form, to_form(default_form_params(), as: :conversion))
     |> allow_upload(:document, accept: @document_accept, max_entries: 10, auto_upload: true)}
  end

  @impl true
  def handle_event("validate", %{"conversion" => params}, socket) do
    {:noreply,
     assign(socket, :form, to_form(Map.merge(default_form_params(), params), as: :conversion))}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :document, ref)}
  end

  @impl true
  def handle_event("convert", %{"conversion" => params}, socket) do
    params = Map.merge(default_form_params(), params)

    case uploaded_entries(socket, :document) do
      {[], []} ->
        {:noreply, put_flash(socket, :error, "Selecione arquivos antes de converter.")}

      {_completed, [_ | _]} ->
        {:noreply, put_flash(socket, :error, "Aguarde o upload terminar antes de converter.")}

      _ ->
        {:noreply,
         convert_uploads(assign(socket, :form, to_form(params, as: :conversion)), params)}
    end
  end

  defp convert_uploads(socket, %{"mode" => "images_to_pdf"}) do
    consumed =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        output_dir =
          Path.join(System.tmp_dir!(), "rapid_tools_live/#{System.unique_integer([:positive])}")

        File.mkdir_p!(output_dir)
        source_path = Path.join(output_dir, entry.client_name)
        File.cp!(path, source_path)
        {:ok, source_path}
      end)

    case PdfConverter.images_to_pdf(consumed, output_dir: Path.dirname(hd(consumed))) do
      {:ok, result} ->
        store_entry = %{
          path: result.output_path,
          filename: result.filename,
          media_type: result.media_type
        }

        {:ok, id} = ConversionStore.put(store_entry)

        socket
        |> assign(:results, [Map.put(result, :download_path, ~p"/downloads/#{id}")])
        |> assign(:batch_download_path, nil)
        |> put_flash(:info, "PDF gerado com sucesso.")

      {:error, _reason} ->
        put_flash(socket, :error, "Os arquivos nao puderam ser convertidos em PDF.")
    end
  end

  defp convert_uploads(socket, %{"mode" => mode}) do
    target_format = if mode == "pdf_to_jpg", do: "jpg", else: "png"

    results =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        output_dir =
          Path.join(System.tmp_dir!(), "rapid_tools_live/#{System.unique_integer([:positive])}")

        File.mkdir_p!(output_dir)
        source_path = Path.join(output_dir, entry.client_name)
        File.cp!(path, source_path)

        case PdfConverter.pdf_to_images(source_path, target_format, output_dir: output_dir) do
          {:ok, converted_results} ->
            stored_results =
              Enum.map(converted_results, fn result ->
                store_entry = %{
                  path: result.output_path,
                  filename: result.filename,
                  media_type: result.media_type
                }

                {:ok, id} = ConversionStore.put(store_entry)
                Map.put(result, :download_path, ~p"/downloads/#{id}")
              end)

            {:ok, {:ok, stored_results}}

          {:error, reason} ->
            {:ok, {:error, reason}}
        end
      end)

    case results do
      converted when is_list(converted) ->
        successful_results =
          converted
          |> Enum.flat_map(fn {:ok, result_list} -> result_list end)

        if successful_results != [] do
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
              |> put_flash(:info, "#{length(successful_results)} paginas convertidas.")

            {:error, _reason} ->
              socket
              |> assign(:results, successful_results)
              |> assign(:batch_download_path, nil)
              |> put_flash(:error, "As paginas foram convertidas, mas o ZIP nao pode ser criado.")
          end
        else
          put_flash(socket, :error, "O PDF nao pode ser convertido.")
        end

      _ ->
        put_flash(socket, :error, "O PDF nao pode ser convertido.")
    end
  end

  defp default_form_params do
    %{"mode" => "pdf_to_png"}
  end

  defp completed_upload_count(entries), do: Enum.count(entries, &(&1.progress == 100))
  defp upload_in_progress?(entries), do: Enum.any?(entries, &(&1.progress < 100))

  defp upload_summary(entries) do
    total = length(entries)
    completed = completed_upload_count(entries)

    cond do
      total == 0 ->
        "Nenhum arquivo selecionado ainda."

      upload_in_progress?(entries) ->
        "#{total} arquivos na fila. #{completed}/#{total} concluidos ate agora, o restante ainda esta enviando."

      true ->
        "#{total} arquivos na fila. #{completed}/#{total} concluidos ate agora."
    end
  end

  defp upload_status_message(entries) do
    cond do
      entries == [] ->
        "Selecione um PDF para extrair paginas ou imagens para montar um novo documento."

      upload_in_progress?(entries) ->
        "Enviando arquivos para o servidor. Aguarde todos chegarem a 100%."

      true ->
        "Uploads concluidos. Agora voce pode converter ou combinar os arquivos."
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
      <section class="min-h-screen bg-[radial-gradient(circle_at_top_left,_rgba(34,197,94,0.16),_transparent_30%),radial-gradient(circle_at_bottom_right,_rgba(163,230,53,0.14),_transparent_28%),linear-gradient(180deg,_rgba(247,254,231,1)_0%,_rgba(255,255,255,1)_52%,_rgba(236,253,245,1)_100%)]">
        <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)]">
            <aside class="rounded-[2rem] border border-lime-100 bg-white/85 p-5 shadow-[0_18px_50px_rgba(15,23,42,0.08)] backdrop-blur">
              <div class="space-y-6">
                <div class="space-y-2">
                  <p class="text-sm font-semibold uppercase tracking-[0.3em] text-lime-700">
                    Rapid Tools
                  </p>
                  <div>
                    <h2 class="text-2xl font-black tracking-tight text-slate-950">Tools</h2>
                    <p class="mt-1 text-sm text-slate-600">
                      Fluxo simples para alternar entre PDF e imagem sem sair do lote.
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
                <span class="inline-flex items-center rounded-full border border-lime-200 bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-lime-700">
                  PDF workflow
                </span>
                <h1 class="text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
                  Convert PDFs and images
                </h1>
                <p class="max-w-3xl text-base text-slate-600 sm:text-lg">
                  Turn PDF pages into PNG or JPG files, or combine multiple images into a single PDF ready to download.
                </p>
                <p class="text-sm text-slate-500">
                  Use PDF to PNG para extrair paginas rapidamente ou Images to PDF para montar um documento final.
                </p>
              </div>

              <div class="grid gap-6 xl:grid-cols-[1.35fr_0.65fr]">
                <div class="rounded-[2rem] border border-white/70 bg-white p-6 shadow-[0_24px_60px_rgba(15,23,42,0.08)]">
                  <.form
                    for={@form}
                    id="pdf-converter-form"
                    phx-change="validate"
                    phx-submit="convert"
                    class="space-y-6"
                  >
                    <div class="rounded-[1.75rem] border border-dashed border-lime-200 bg-lime-50/60 p-5">
                      <div class="space-y-2">
                        <label for="pdf-upload" class="text-sm font-semibold text-slate-900">
                          Arquivos de origem
                        </label>
                        <.live_file_input
                          upload={@uploads.document}
                          id="pdf-upload"
                          class="block w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700 shadow-sm transition file:mr-4 file:rounded-xl file:border-0 file:bg-slate-950 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-white hover:border-lime-300"
                        />
                        <p class="text-sm text-slate-500">
                          Entradas aceitas: PDF, JPG, JPEG, PNG e WEBP.
                        </p>
                      </div>

                      <div
                        id="pdf-upload-list"
                        class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                      >
                        <div class="sticky top-0 z-10 rounded-2xl border border-lime-100 bg-lime-50/95 px-4 py-3 text-sm font-medium text-lime-900 backdrop-blur">
                          {upload_summary(@uploads.document.entries)}
                        </div>
                        <div
                          :for={entry <- @uploads.document.entries}
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
                            {if entry.progress == 100, do: "pronto", else: "#{entry.progress}%"}
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
                      field={@form[:mode]}
                      type="select"
                      label="Modo"
                      options={[
                        {"PDF to PNG", "pdf_to_png"},
                        {"PDF to JPG", "pdf_to_jpg"},
                        {"Images to PDF", "images_to_pdf"}
                      ]}
                    />

                    <button
                      type="submit"
                      id="pdf-convert-button"
                      phx-disable-with="Convertendo arquivos..."
                      disabled={
                        @uploads.document.entries == [] ||
                          upload_in_progress?(@uploads.document.entries)
                      }
                      class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-lime-700 disabled:cursor-wait disabled:opacity-90"
                    >
                      <span>Converter arquivos</span>
                    </button>

                    <p class="text-sm text-slate-500">
                      {upload_status_message(@uploads.document.entries)}
                    </p>
                  </.form>
                </div>

                <aside class="rounded-[2rem] border border-white/70 bg-slate-950 p-6 text-white shadow-[0_24px_60px_rgba(15,23,42,0.16)]">
                  <div :if={@results != []} class="space-y-4">
                    <p class="text-sm font-semibold uppercase tracking-[0.25em] text-lime-300">
                      {length(@results)} arquivos prontos
                    </p>
                    <a
                      :if={@batch_download_path}
                      href={@batch_download_path}
                      class="inline-flex w-full items-center justify-center rounded-2xl bg-lime-400 px-4 py-3 text-sm font-semibold text-slate-950 transition hover:bg-lime-300"
                    >
                      Baixar pacote ZIP
                    </a>
                    <div class="space-y-3">
                      <div
                        :for={result <- @results}
                        class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4"
                      >
                        <p class="font-semibold">{result.filename}</p>
                        <a
                          href={result.download_path}
                          class="mt-3 inline-flex w-full items-center justify-center rounded-2xl border border-white/10 bg-white/10 px-4 py-3 text-sm font-semibold text-white transition hover:bg-white/20"
                        >
                          Baixar arquivo
                        </a>
                      </div>
                    </div>
                  </div>

                  <div :if={@results == []} class="space-y-4">
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold uppercase tracking-[0.25em] text-lime-300">
                        PDF to PNG
                      </p>
                      <p class="mt-3 text-sm text-slate-300">
                        Extraia paginas para thumbnails, galerias, anexos de suporte ou revisao visual.
                      </p>
                    </div>
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold text-white">Images to PDF</p>
                      <p class="mt-2 text-sm text-slate-300">
                        Junte capturas, documentos escaneados e artes soltas em um unico PDF.
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
