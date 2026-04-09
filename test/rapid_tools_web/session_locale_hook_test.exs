defmodule RapidToolsWeb.SessionLocaleHookTest do
  use ExUnit.Case, async: true

  alias RapidToolsWeb.SessionLocaleHook

  test "applies the session locale to the liveview process and socket assigns" do
    socket = %Phoenix.LiveView.Socket{}

    assert {:cont, updated_socket} =
             SessionLocaleHook.on_mount(:default, %{}, %{"locale" => "pt_BR"}, socket)

    assert updated_socket.assigns.current_locale == "pt_BR"
    assert Gettext.get_locale(RapidToolsWeb.Gettext) == "pt_BR"
  end

  test "falls back to en when there is no locale in the liveview session" do
    socket = %Phoenix.LiveView.Socket{}

    assert {:cont, updated_socket} = SessionLocaleHook.on_mount(:default, %{}, %{}, socket)

    assert updated_socket.assigns.current_locale == "en"
    assert Gettext.get_locale(RapidToolsWeb.Gettext) == "en"
  end
end
