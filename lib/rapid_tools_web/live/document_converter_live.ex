defmodule RapidToolsWeb.DocumentConverterLive do
  use RapidToolsWeb, :live_view

  alias RapidTools.ConversionStore
  alias RapidTools.DocumentConverter
  alias RapidTools.ZipArchive
  alias RapidToolsWeb.ToolNavigation

  @impl true
  def mount(_params, session, socket) do
    locale =
      Locale.set_gettext_locale(
        session["locale"] || socket.assigns[:current_locale] || Locale.default_locale()
      )

    {:ok,
     socket
     |> assign(:current_locale, locale)
     |> assign(:tools, ToolNavigation.tools("document-converter"))
     |> assign(:extractor_enabled, DocumentConverter.supported_mode?("pdf_to_md_clean"))
     |> assign(:office_conversion_enabled, DocumentConverter.supported_mode?("docx_to_pdf"))
     |> assign(:results, [])
     |> assign(:batch_download_path, nil)
     |> assign(:mode_options, mode_options())
     |> assign(:form, to_form(default_form_params(), as: :conversion))
     |> assign(:my_path, "/document-converter")
     |> allow_upload(:document,
       accept: DocumentConverter.accept_extensions(),
       max_entries: 10,
       auto_upload: true
     )}
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
    mode = params["mode"]

    case uploaded_entries(socket, :document) do
      {[], []} ->
        {:noreply, put_flash(socket, :error, gettext("Selecione arquivos antes de converter."))}

      {_completed, [_ | _]} ->
        {:noreply,
         put_flash(socket, :error, gettext("Aguarde o upload terminar antes de converter."))}

      _ ->
        case invalid_uploads_for_mode(socket.assigns.uploads.document.entries, mode) do
          [] ->
            {:noreply,
             convert_uploads(assign(socket, :form, to_form(params, as: :conversion)), mode)}

          invalid_entries ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Alguns arquivos nao combinam com o modo escolhido: %{files}.",
                 files: Enum.join(invalid_entries, ", ")
               )
             )}
        end
    end
  end

  defp convert_uploads(socket, "images_to_pdf") do
    consumed =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        output_dir =
          Path.join(System.tmp_dir!(), "rapid_tools_live/#{System.unique_integer([:positive])}")

        File.mkdir_p!(output_dir)
        source_path = Path.join(output_dir, entry.client_name)
        File.cp!(path, source_path)
        {:ok, source_path}
      end)

    case DocumentConverter.combine_as_pdf(consumed, output_dir: Path.dirname(hd(consumed))) do
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
        |> put_flash(:info, gettext("Documento gerado com sucesso."))

      {:error, _reason} ->
        put_flash(socket, :error, gettext("Os arquivos nao puderam ser combinados em PDF."))
    end
  end

  defp convert_uploads(socket, mode) do
    results =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        output_dir =
          Path.join(System.tmp_dir!(), "rapid_tools_live/#{System.unique_integer([:positive])}")

        File.mkdir_p!(output_dir)
        source_path = Path.join(output_dir, entry.client_name)
        File.cp!(path, source_path)

        case DocumentConverter.convert(source_path, mode, output_dir: output_dir) do
          {:ok, converted_results} ->
            converted_results
            |> List.wrap()
            |> Enum.map(&store_result/1)
            |> then(&{:ok, {:ok, &1}})

          {:error, reason} ->
            {:ok, {:error, reason}}
        end
      end)

    case successful_results(results) do
      {:ok, successful_results} ->
        build_batch_response(
          socket,
          successful_results,
          success_message(mode, length(successful_results)),
          gettext("Os arquivos foram convertidos, mas o ZIP nao pode ser criado.")
        )

      :error ->
        put_flash(socket, :error, gettext("O documento nao pode ser convertido."))
    end
  end

  defp store_result(result) do
    store_entry = %{
      path: result.output_path,
      filename: result.filename,
      media_type: result.media_type
    }

    {:ok, id} = ConversionStore.put(store_entry)
    Map.put(result, :download_path, ~p"/downloads/#{id}")
  end

  defp successful_results(converted) when is_list(converted) do
    successful_results =
      converted
      |> Enum.flat_map(fn
        {:ok, result_list} -> result_list
        _ -> []
      end)

    if successful_results != [] do
      {:ok, successful_results}
    else
      :error
    end
  end

  defp successful_results(_), do: :error

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

  defp invalid_uploads_for_mode(entries, mode) do
    allowed_extensions = DocumentConverter.source_extensions_for_mode(mode)

    Enum.flat_map(entries, fn entry ->
      ext = entry.client_name |> Path.extname() |> String.downcase()
      if ext in allowed_extensions, do: [], else: [entry.client_name]
    end)
  end

  defp success_message("pdf_to_png", count),
    do: gettext("%{count} pages converted.", count: count)

  defp success_message("pdf_to_jpg", count),
    do: gettext("%{count} pages converted.", count: count)

  defp success_message(_mode, count),
    do: gettext("%{count} documents converted.", count: count)

  defp default_form_params do
    %{"mode" => "pdf_to_png"}
  end

  defp mode_options do
    [
      {gettext("PDF to PNG"), "pdf_to_png"},
      {gettext("PDF to JPG"), "pdf_to_jpg"},
      {gettext("PDF to Markdown (Clean)"), "pdf_to_md_clean"},
      {gettext("PDF to Markdown (Fidelity)"), "pdf_to_md_fidelity"},
      {gettext("PDF to DOCX"), "pdf_to_docx"},
      {gettext("Markdown to PDF"), "md_to_pdf"},
      {gettext("Markdown to DOCX"), "md_to_docx"},
      {gettext("Images to PDF"), "images_to_pdf"},
      {gettext("DOCX to PDF"), "docx_to_pdf"},
      {gettext("DOCX to Markdown (Clean)"), "docx_to_md_clean"},
      {gettext("DOCX to Markdown (Fidelity)"), "docx_to_md_fidelity"},
      {gettext("ODT to PDF"), "odt_to_pdf"},
      {gettext("RTF to PDF"), "rtf_to_pdf"},
      {gettext("TXT to PDF"), "txt_to_pdf"},
      {gettext("HTML to PDF"), "html_to_pdf"}
    ]
    |> Enum.filter(fn {_label, mode} -> DocumentConverter.supported_mode?(mode) end)
  end

  defp accepted_inputs_copy do
    DocumentConverter.accept_extensions()
    |> Enum.map(&String.trim_leading(&1, "."))
    |> Enum.map_join(", ", &String.upcase/1)
    |> then(&gettext("Entradas aceitas: %{formats}.", formats: &1))
  end

  defp completed_upload_count(entries), do: Enum.count(entries, &(&1.progress == 100))
  defp upload_in_progress?(entries), do: Enum.any?(entries, &(&1.progress < 100))

  defp upload_summary(entries) do
    total = length(entries)
    completed = completed_upload_count(entries)

    cond do
      total == 0 ->
        gettext("Nenhum arquivo selecionado ainda.")

      upload_in_progress?(entries) ->
        gettext(
          "%{total} files in queue. %{completed}/%{total} finished so far, the rest are still uploading.",
          total: total,
          completed: completed
        )

      true ->
        gettext("%{total} files in queue. %{completed}/%{total} finished so far.",
          total: total,
          completed: completed
        )
    end
  end

  defp upload_status_message(entries) do
    cond do
      entries == [] ->
        gettext("Selecione PDFs, documentos de texto ou imagens para habilitar a conversao.")

      upload_in_progress?(entries) ->
        gettext("Enviando arquivos para o servidor. Aguarde todos chegarem a 100%.")

      true ->
        gettext("Uploads concluidos. Agora voce pode converter em lote.")
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
      <section class="min-h-screen bg-[radial-gradient(circle_at_top_left,_rgba(124,58,237,0.16),_transparent_30%),radial-gradient(circle_at_bottom_right,_rgba(59,130,246,0.12),_transparent_28%),linear-gradient(180deg,_rgba(247,245,255,1)_0%,_rgba(255,255,255,1)_52%,_rgba(245,247,255,1)_100%)]">
        <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <div class="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)]">
            <.tool_sidebar
              tools={@tools}
              current_locale={@current_locale}
              redirect_to={@my_path}
              theme={%{sidebar_border_class: "border-violet-100", accent_class: "text-violet-700"}}
            />

            <div class="space-y-6">
              <div class="space-y-4 px-2 py-2">
                <span class="inline-flex items-center rounded-full border border-violet-200 bg-white/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-violet-700">
                  {gettext("Document workflow")}
                </span>
                <h1 class="text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
                  {gettext("Convert PDFs, documents and text files")}
                </h1>
                <p class="max-w-3xl text-base text-slate-600 sm:text-lg">
                  {cond do
                    @extractor_enabled and @office_conversion_enabled ->
                      gettext(
                        "Convert PDFs to Markdown or DOCX, convert Markdown to PDF or DOCX, and send DOCX back to PDF or Markdown with clean and fidelity modes."
                      )

                    @extractor_enabled ->
                      gettext(
                        "Convert PDFs to Markdown or DOCX and send DOCX back to Markdown with clean or fidelity modes. Markdown to PDF and Markdown to DOCX appear automatically when the runtime supports LibreOffice."
                      )

                    @office_conversion_enabled ->
                      gettext(
                        "Convert Markdown to PDF or DOCX and DOCX to PDF. PDF extraction modes appear automatically when the runtime supports the document extractor."
                      )

                    true ->
                      gettext(
                        "Convert PDFs in image workflows and combine images into PDF with individual or batch downloads."
                      )
                  end}
                </p>
                <p class="text-sm text-slate-500">
                  {gettext(
                    "Ideal for contracts, documentation, attachments, scans and files that need to move between PDF, Markdown and DOCX."
                  )}
                </p>
              </div>

              <div id="document-converter-panel" class="grid gap-6 xl:grid-cols-[1.35fr_0.65fr]">
                <div class="rounded-[2rem] border border-white/70 bg-white p-6 shadow-[0_24px_60px_rgba(15,23,42,0.08)]">
                  <.form
                    for={@form}
                    id="document-converter-form"
                    phx-change="validate"
                    phx-submit="convert"
                    class="space-y-6"
                  >
                    <div class="rounded-[1.75rem] border border-dashed border-violet-200 bg-violet-50/60 p-5">
                      <div class="space-y-2">
                        <label for="document-upload" class="text-sm font-semibold text-slate-900">
                          {gettext("Arquivos de origem")}
                        </label>
                        <.live_file_input
                          upload={@uploads.document}
                          id="document-upload"
                          class="block w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700 shadow-sm transition file:mr-4 file:rounded-xl file:border-0 file:bg-slate-950 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-white hover:border-violet-300"
                        />
                        <p class="text-sm text-slate-500">
                          {accepted_inputs_copy()}
                        </p>
                      </div>

                      <div
                        id="document-upload-list"
                        class="mt-4 max-h-[22rem] space-y-2 overflow-y-auto pr-1"
                      >
                        <div class="sticky top-0 z-10 rounded-2xl border border-violet-100 bg-violet-50/95 px-4 py-3 text-sm font-medium text-violet-900 backdrop-blur">
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
                                class="h-2 rounded-full bg-violet-500 transition-all"
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
                            aria-label={gettext("Remove %{filename}", filename: entry.client_name)}
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
                      label={gettext("Modo")}
                      options={@mode_options}
                    />

                    <button
                      type="submit"
                      id="document-convert-button"
                      phx-disable-with={gettext("Converting files...")}
                      disabled={
                        @uploads.document.entries == [] ||
                          upload_in_progress?(@uploads.document.entries)
                      }
                      class="inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-violet-700 disabled:cursor-wait disabled:opacity-90"
                    >
                      <span>{gettext("Converter arquivos")}</span>
                    </button>

                    <p class="text-sm text-slate-500">
                      {upload_status_message(@uploads.document.entries)}
                    </p>
                  </.form>
                </div>

                <aside class="rounded-[2rem] border border-white/70 bg-slate-950 p-6 text-white shadow-[0_24px_60px_rgba(15,23,42,0.16)]">
                  <div :if={@results != []} class="space-y-4">
                    <p class="text-sm font-semibold uppercase tracking-[0.25em] text-violet-300">
                      {gettext("%{count} files ready", count: length(@results))}
                    </p>
                    <a
                      :if={@batch_download_path}
                      href={@batch_download_path}
                      class="inline-flex w-full items-center justify-center rounded-2xl bg-violet-300 px-4 py-3 text-sm font-semibold text-slate-950 transition hover:bg-violet-200"
                    >
                      {gettext("Baixar pacote ZIP")}
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
                          {gettext("Baixar arquivo")}
                        </a>
                      </div>
                    </div>
                  </div>

                  <div :if={@results == []} class="space-y-4">
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
                      <p class="text-sm font-semibold uppercase tracking-[0.25em] text-violet-300">
                        {gettext("PDF to PNG")}
                      </p>
                      <p class="mt-3 text-sm text-slate-300">
                        {gettext(
                          "Extraia paginas para thumbnails, revisoes, anexos e fluxos de aprovacao."
                        )}
                      </p>
                    </div>
                    <div
                      :if={@extractor_enabled}
                      class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4"
                    >
                      <p class="text-sm font-semibold text-white">
                        {gettext("PDF to Markdown and DOCX")}
                      </p>
                      <p class="mt-2 text-sm text-slate-300">
                        {gettext(
                          "Use clean for editing, fidelity for structure, PDF to DOCX for editable exports, and DOCX to Markdown for roundtrips."
                        )}
                      </p>
                    </div>
                    <div
                      :if={!@extractor_enabled}
                      class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4"
                    >
                      <p class="text-sm font-semibold text-white">
                        {gettext("PDF extraction modes are unavailable")}
                      </p>
                      <p class="mt-2 text-sm text-slate-300">
                        {gettext(
                          "Install the document extractor to enable PDF to Markdown (Clean), PDF to Markdown (Fidelity) and PDF to DOCX."
                        )}
                      </p>
                    </div>
                    <div
                      :if={@office_conversion_enabled}
                      class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4"
                    >
                      <p class="text-sm font-semibold text-white">
                        {gettext("Markdown and DOCX to PDF")}
                      </p>
                      <p class="mt-2 text-sm text-slate-300">
                        {gettext(
                          "Export Markdown to PDF or DOCX, and DOCX to PDF, when LibreOffice is available."
                        )}
                      </p>
                    </div>
                    <div
                      :if={!@office_conversion_enabled}
                      class="rounded-[1.5rem] border border-white/10 bg-white/5 p-4"
                    >
                      <p class="text-sm font-semibold text-white">
                        {gettext("Unlock office document modes")}
                      </p>
                      <p class="mt-2 text-sm text-slate-300">
                        {gettext(
                          "Install a working LibreOffice on the server to enable Markdown to PDF, Markdown to DOCX and DOCX to PDF."
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
