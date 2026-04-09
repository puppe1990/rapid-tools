defmodule RapidToolsWeb.LocaleController do
  @moduledoc """
  Controller for switching between locales.
  """
  use RapidToolsWeb, :controller

  alias RapidToolsWeb.Locale

  def switch(conn, %{"locale" => locale}) do
    locale = Locale.validate_locale(locale)

    conn
    |> put_session("locale", locale)
    |> redirect(to: get_redirect_path(conn))
  end

  defp get_redirect_path(conn) do
    case conn.params["redirect_to"] do
      nil -> "/"
      path -> path
    end
  end
end
