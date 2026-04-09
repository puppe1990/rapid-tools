defmodule RapidToolsWeb.SessionLocaleHook do
  @moduledoc """
  Phoenix LiveView on_mount hook that reads locale from session and assigns it.
  """
  alias RapidToolsWeb.Locale

  def on_mount(:default, _params, %{"locale" => locale}, socket) when is_binary(locale) do
    locale = Locale.set_gettext_locale(locale)
    {:cont, Phoenix.Component.assign(socket, :current_locale, locale)}
  end

  def on_mount(:default, _params, _session, socket) do
    locale = Locale.set_gettext_locale(Locale.default_locale())
    {:cont, Phoenix.Component.assign(socket, :current_locale, locale)}
  end
end
