defmodule RapidToolsWeb.RouteLocaleConsistencyTest do
  use RapidToolsWeb.ConnCase, async: false

  test "detects pt_BR from the accept-language header when there is no locale in session", %{
    conn: conn
  } do
    conn = put_req_header(conn, "accept-language", "pt-BR,pt;q=0.9,en;q=0.8")

    {:ok, view, html} = live(conn, ~p"/")

    assert has_element?(view, "nav[aria-label=\"Ferramentas\"]")
    assert html =~ "Conversor de Imagem"
    assert html =~ "Ferramentas"
  end

  test "en routes keep hero and panel copy fully localized in English", %{conn: conn} do
    localized_expectations = [
      {~p"/image-resizer", "Image sizing", "Ready-made presets", "Escolha um preset pronto"},
      {~p"/video-compressor", "Video optimization", "Small size",
       "Escolha um preset de compressao"},
      {~p"/extract-audio", "Audio extraction", "Batch download", "audios extraidos"},
      {~p"/document-converter", "Document workflow", "PDF to PNG",
       "Use PDF to PNG para extrair paginas"},
      {~p"/photos-to-pdf", "Photo layout", "How it works", "respeita a ordem mostrada na fila"},
      {~p"/together-audios", "Audio assembly", "How it works", "Junte varios arquivos de audio"}
    ]

    for {path, localized_hero, localized_panel, leaked_copy} <- localized_expectations do
      {:ok, _view, html} = live(conn, path)

      assert html =~ localized_hero
      assert html =~ localized_panel
      refute html =~ leaked_copy
    end
  end

  test "pt_BR renders localized hero and info panel copy across tool routes", %{conn: conn} do
    conn = init_test_session(conn, %{"locale" => "pt_BR"})

    localized_expectations = [
      {~p"/image-resizer", "Dimensionamento de imagens", "Presets prontos"},
      {~p"/video-compressor", "Otimização de vídeos", "Tamanho reduzido"},
      {~p"/extract-audio", "Extração de áudio", "Download em lote"},
      {~p"/document-converter", "Fluxo de documentos", "PDF para PNG"},
      {~p"/photos-to-pdf", "Photos to PDF", "Como funciona"},
      {~p"/together-audios", "Montagem de áudio", "Como funciona"}
    ]

    for {path, localized_hero, localized_panel} <- localized_expectations do
      {:ok, _view, html} = live(conn, path)

      assert html =~ localized_hero
      assert html =~ localized_panel
    end
  end
end
