defmodule RapidToolsWeb.Locale do
  @moduledoc """
  Helpers for managing the current locale and translations.
  """

  @supported_locales ["en", "pt_BR"]
  @default_locale "en"

  @doc """
  Returns the list of supported locales.
  """
  def supported_locales, do: @supported_locales

  @doc """
  Returns the default locale.
  """
  def default_locale, do: @default_locale

  @doc """
  Validates and returns a locale, falling back to default.
  """
  def validate_locale(locale) when locale in @supported_locales, do: locale
  def validate_locale(_), do: @default_locale

  @doc """
  Returns the locale display name.
  """
  def display_name("en"), do: "English"
  def display_name("pt_BR"), do: "Português (BR)"
  def display_name(_), do: "Unknown"

  @doc """
  Returns the language code for HTML lang attribute.
  """
  def lang_code("pt_BR"), do: "pt-BR"
  def lang_code(locale), do: locale

  @doc """
  Sets the Gettext locale.
  """
  def set_gettext_locale(locale) do
    locale = validate_locale(locale)
    Gettext.put_locale(RapidToolsWeb.Gettext, locale)
    locale
  end

  @doc """
  Returns the alternate locale for toggling.
  """
  def toggle_locale("en"), do: "pt_BR"
  def toggle_locale("pt_BR"), do: "en"
  def toggle_locale(_), do: "pt_BR"
end
