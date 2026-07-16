defmodule RapidToolsWeb.VideoCompressorLiveTest do
  use RapidToolsWeb.ConnCase, async: false

  alias RapidTools.TestSupport.ImageFixtures

  defp eventually_render_including(view, expected, attempts \\ 40)

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

  defp temp_video_stage(client_name) do
    source_path = ImageFixtures.tiny_mp4_path!("stage-#{client_name}")
    output_dir = ImageFixtures.temp_dir!("video-compressor-stage")
    staged_path = Path.join(output_dir, client_name)
    File.cp!(source_path, staged_path)

    %{source_path: staged_path, client_name: client_name, output_dir: output_dir}
  end

  test "renders the video compressor interface", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/video-compressor")

    assert has_element?(view, "form#video-compressor-form")
    assert has_element?(view, "#video-compress-button")
    assert has_element?(view, "#video-compressor-upload-list")
    assert has_element?(view, "a[href=\"/video-compressor\"]", "Video Compressor")
    assert html =~ "Compress videos for sharing"
    assert html =~ "Small size"
    assert html =~ ~s(value="balanced")
  end

  test "accepts multiple selected videos in the upload list", %{conn: conn} do
    source_path_1 = ImageFixtures.tiny_mp4_path!("compress-live-1.mp4")
    source_path_2 = ImageFixtures.tiny_mp4_path!("compress-live-2.mp4")
    {:ok, view, _html} = live(conn, ~p"/video-compressor")

    upload =
      file_input(view, "#video-compressor-form", :video, [
        %{
          last_modified: 1_711_000_000_000,
          name: "compress-1.mp4",
          content: File.read!(source_path_1),
          type: "video/mp4"
        },
        %{
          last_modified: 1_711_000_000_001,
          name: "compress-2.mp4",
          content: File.read!(source_path_2),
          type: "video/mp4"
        }
      ])

    rendered_upload = render_upload(upload, "compress-1.mp4")
    assert rendered_upload =~ "compress-1.mp4"
    assert rendered_upload =~ "compress-2.mp4"
    assert rendered_upload =~ "2 videos in queue. 1/2 finished so far"
  end

  test "compresses an uploaded video asynchronously without dropping the LiveView", %{conn: conn} do
    source_path = ImageFixtures.tiny_mp4_path!("compress-live-success.mp4")
    {:ok, view, _html} = live(conn, ~p"/video-compressor")

    upload =
      file_input(view, "#video-compressor-form", :video, [
        %{
          last_modified: 1_711_000_000_002,
          name: "clip.mp4",
          content: File.read!(source_path),
          type: "video/mp4"
        }
      ])

    assert render_upload(upload, "clip.mp4") =~ "clip.mp4"

    view
    |> form("#video-compressor-form",
      compression: %{preset: "small", max_resolution: "480"}
    )
    |> render_submit()

    html = eventually_render_including(view, "videos ready")
    assert html =~ "videos ready"
    assert html =~ "Download video"
    assert html =~ "-compressed.mp4"
  end

  test "surfaces a friendly error when uploaded entries become unavailable before compression", %{
    conn: conn
  } do
    source_path = ImageFixtures.tiny_mp4_path!("stale-upload-compress.mp4")
    {:ok, view, _html} = live(conn, ~p"/video-compressor")

    upload =
      file_input(view, "#video-compressor-form", :video, [
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
      |> form("#video-compressor-form",
        compression: %{preset: "balanced", max_resolution: "original"}
      )
      |> render_submit()

    assert html =~ "This video upload was lost before compression."
    assert html =~ "stale.mp4"
  end

  test "shows which video is currently being compressed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/video-compressor")

    :sys.replace_state(view.pid, fn state ->
      socket = state.socket
      updated_socket = Phoenix.Component.assign(socket, :processing_total, 2)
      %{state | socket: updated_socket}
    end)

    send(
      view.pid,
      {:begin_video_compression,
       [
         temp_video_stage("progress-demo.mp4"),
         temp_video_stage("next-up.mov")
       ], %{"preset" => "small", "max_resolution" => "480", "mute" => "false"}, []}
    )

    html = eventually_render_including(view, "Compressing now")
    assert html =~ "Compressing now"
    assert html =~ "progress-demo.mp4" or html =~ "next-up.mov"
    assert html =~ "of 2 videos"
  end
end
