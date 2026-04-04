defmodule RapidToolsWeb.VideoConverterLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  defp eventually_render_including(view, expected, attempts \\ 20)

  defp eventually_render_including(view, _expected, 1), do: render(view)

  defp eventually_render_including(view, expected, attempts) do
    html = render(view)

    if html =~ expected do
      html
    else
      Process.sleep(50)
      eventually_render_including(view, expected, attempts - 1)
    end
  end

  defp temp_video_stage(name) do
    output_dir = ImageFixtures.temp_dir!("video-stage-#{System.unique_integer([:positive])}")
    source_path = ImageFixtures.tiny_mp4_path!(name)

    %{
      source_path: source_path,
      client_name: name,
      output_dir: output_dir
    }
  end

  test "renders the video converter interface", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    assert has_element?(view, "form#video-converter-form")
    assert has_element?(view, "#video-convert-button")
    assert has_element?(view, "#video-upload-list")
    assert has_element?(view, "#video-converter-form .phx-submit-loading\\:flex")
    assert has_element?(view, "a[href=\"/\"]", "Image Converter")
    assert has_element?(view, "a[href=\"/image-resizer\"]", "Image Resizer")
    assert has_element?(view, "a[href=\"/video-converter\"]", "Video Converter")
    assert has_element?(view, "a[href=\"/video-compressor\"]", "Video Compressor")
    assert has_element?(view, "a[href=\"/audio-converter\"]", "Audio Converter")
    assert has_element?(view, "a[href=\"/pdf-converter\"]", "PDF Converter")
    assert has_element?(view, "a[href=\"/together-audios\"]", "Together Audios")
    assert render(view) =~ "Converta videos para MP4, MOV, WEBM, MKV, AVI e TS"
    assert render(view) =~ "Convertendo video"
    assert render(view) =~ "Isso pode levar alguns segundos."
    assert render(view) =~ "Nenhum video selecionado ainda."
    assert render(view) =~ ~s(value="mp4")
  end

  test "accepts multiple selected videos in the upload list", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_mp4_path!("live-upload-video-1.mp4")
    source_path_2 = ImageFixtures.tiny_mp4_path!("live-upload-video-2.mp4")
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    upload =
      file_input(view, "#video-converter-form", :video, [
        %{
          last_modified: 1_711_000_000_000,
          name: "sample-1.mp4",
          content: File.read!(source_path_1),
          type: "video/mp4"
        },
        %{
          last_modified: 1_711_000_000_001,
          name: "sample-2.mp4",
          content: File.read!(source_path_2),
          type: "video/mp4"
        }
      ])

    rendered_upload = render_upload(upload, "sample-1.mp4")
    assert rendered_upload =~ "sample-1.mp4"
    assert rendered_upload =~ "sample-2.mp4"
    assert rendered_upload =~ "2 videos na fila. 1/2 concluidos ate agora"
    assert rendered_upload =~ "Remover sample-1.mp4"
    assert rendered_upload =~ "phx-click=\"cancel-upload\""
  end

  test "accepts webm uploads even when the browser falls back to application/octet-stream", %{
    conn: conn
  } do
    source_path = ImageFixtures.tiny_mp4_path!("live-upload-video-webm.mp4")
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    upload =
      file_input(view, "#video-converter-form", :video, [
        %{
          last_modified: 1_711_000_000_002,
          name: "recording.webm",
          content: File.read!(source_path),
          type: "application/octet-stream"
        }
      ])

    rendered_upload = render_upload(upload, "recording.webm")
    assert rendered_upload =~ "recording.webm"
    assert rendered_upload =~ "pronto"
    refute rendered_upload =~ "Formato nao aceito"
  end

  test "accepts ts uploads", %{conn: conn} do
    source_path = ImageFixtures.tiny_mp4_path!("live-upload-video-ts.mp4")
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    upload =
      file_input(view, "#video-converter-form", :video, [
        %{
          last_modified: 1_711_000_000_005,
          name: "broadcast.ts",
          content: File.read!(source_path),
          type: "video/mp2t"
        }
      ])

    rendered_upload = render_upload(upload, "broadcast.ts")
    assert rendered_upload =~ "broadcast.ts"
    assert rendered_upload =~ "pronto"
    refute rendered_upload =~ "Formato nao aceito"
  end

  test "accepts ts uploads when the browser falls back to application/octet-stream", %{
    conn: conn
  } do
    source_path = ImageFixtures.tiny_mp4_path!("live-upload-video-ts-octet.mp4")
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    upload =
      file_input(view, "#video-converter-form", :video, [
        %{
          last_modified: 1_711_000_000_006,
          name: "camera-export.ts",
          content: File.read!(source_path),
          type: "application/octet-stream"
        }
      ])

    rendered_upload = render_upload(upload, "camera-export.ts")
    assert rendered_upload =~ "camera-export.ts"
    assert rendered_upload =~ "pronto"
    refute rendered_upload =~ "Formato nao aceito"
  end

  test "accepts uppercase TS uploads", %{conn: conn} do
    source_path = ImageFixtures.tiny_mp4_path!("live-upload-video-uppercase-ts.mp4")
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    upload =
      file_input(view, "#video-converter-form", :video, [
        %{
          last_modified: 1_711_000_000_007,
          name: "CAM001.TS",
          content: File.read!(source_path),
          type: "video/mp2t"
        }
      ])

    rendered_upload = render_upload(upload, "CAM001.TS")
    assert rendered_upload =~ "CAM001.TS"
    assert rendered_upload =~ "pronto"
    refute rendered_upload =~ "Formato nao aceito"
  end

  test "shows an explicit initial status message", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    assert render(view) =~ "Selecione um ou mais videos para habilitar a conversao."
  end

  test "shows a specific error flash instead of crashing when media is invalid", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    upload =
      file_input(view, "#video-converter-form", :video, [
        %{
          last_modified: 1_711_000_000_003,
          name: "broken.mp4",
          content: "not-a-real-video",
          type: "video/mp4"
        }
      ])

    assert render_upload(upload, "broken.mp4") =~ "broken.mp4"

    _html =
      view
      |> form("#video-converter-form", conversion: %{target_format: "mp4"})
      |> render_submit()

    html = eventually_render_including(view, "Este arquivo parece corrompido ou incompleto.")
    assert html =~ "Este arquivo parece corrompido ou incompleto."
  end

  test "shows a specific error for mp4 files without a video track", %{conn: conn} do
    source_path = ImageFixtures.audio_only_mp4_path!("audio-only-upload.mp4")
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    upload =
      file_input(view, "#video-converter-form", :video, [
        %{
          last_modified: 1_711_000_000_004,
          name: "audio-only.mp4",
          content: File.read!(source_path),
          type: "video/mp4"
        }
      ])

    assert render_upload(upload, "audio-only.mp4") =~ "audio-only.mp4"

    _html =
      view
      |> form("#video-converter-form", conversion: %{target_format: "webm"})
      |> render_submit()

    html = eventually_render_including(view, "Este arquivo nao possui uma trilha de video.")
    assert html =~ "Este arquivo nao possui uma trilha de video."
  end

  test "surfaces a friendly error when uploaded entries become unavailable before conversion", %{
    conn: conn
  } do
    source_path = ImageFixtures.tiny_mp4_path!("stale-upload-video.mp4")
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    upload =
      file_input(view, "#video-converter-form", :video, [
        %{
          last_modified: 1_711_000_000_008,
          name: "stale.mp4",
          content: File.read!(source_path),
          type: "video/mp4"
        }
      ])

    assert render_upload(upload, "stale.mp4") =~ "stale.mp4"

    dead_pid = spawn(fn -> :ok end)
    Process.sleep(10)
    refute Process.alive?(dead_pid)

    :sys.replace_state(view.pid, fn state ->
      socket = state.socket
      conf = socket.assigns.uploads.video
      [entry] = conf.entries

      updated_conf = %{
        conf
        | entry_refs_to_pids: Map.put(conf.entry_refs_to_pids, entry.ref, dead_pid)
      }

      updated_uploads = Map.put(socket.assigns.uploads, :video, updated_conf)
      updated_socket = %{socket | assigns: Map.put(socket.assigns, :uploads, updated_uploads)}

      %{state | socket: updated_socket}
    end)

    html =
      view
      |> form("#video-converter-form", conversion: %{target_format: "mp4"})
      |> render_submit()

    assert html =~ "O upload deste video foi perdido antes da conversao."
    assert html =~ "stale.mp4"
  end

  test "shows which video is currently being converted", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/video-converter")

    :sys.replace_state(view.pid, fn state ->
      socket = state.socket
      updated_socket = Phoenix.Component.assign(socket, :processing_total, 2)
      %{state | socket: updated_socket}
    end)

    send(
      view.pid,
      {:begin_video_conversion,
       [
         temp_video_stage("progress-demo.mp4"),
         temp_video_stage("next-up.mov")
       ], "mp4", []}
    )

    html = eventually_render_including(view, "Convertendo agora")
    assert html =~ "Convertendo agora"
    assert html =~ "progress-demo.mp4" or html =~ "next-up.mov"
    assert html =~ "de 2 videos"
  end
end
