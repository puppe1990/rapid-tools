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
        Locale.default_locale()
        |> Locale.validate_locale()

    Locale.set_gettext_locale(locale)

    assign(conn, :current_locale, locale)
  end
end
