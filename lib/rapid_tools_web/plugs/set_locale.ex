defmodule RapidToolsWeb.Plugs.SetLocale do
  @moduledoc """
  Plug that sets the locale for each request based on session.
  """
  import Plug.Conn
  alias RapidToolsWeb.Locale

  def init(default), do: default

  def call(conn, _default) do
    locale =
      get_session(conn, "locale") ||
        conn
        |> get_req_header("accept-language")
        |> List.first()
        |> Locale.detect_locale()
        |> Locale.validate_locale()

    Locale.set_gettext_locale(locale)

    conn
    |> maybe_store_locale(locale)
    |> assign(:current_locale, locale)
  end

  defp maybe_store_locale(conn, locale) do
    if get_session(conn, "locale") do
      conn
    else
      put_session(conn, "locale", locale)
    end
  end
end
