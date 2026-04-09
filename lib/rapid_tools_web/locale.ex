defmodule RapidToolsWeb.Locale do
  @moduledoc """
  Helpers for managing the current locale and translations.
  """
  use Gettext, backend: RapidToolsWeb.Gettext

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
  Detects the best supported locale from an Accept-Language header.
  """
  def detect_locale(nil), do: @default_locale
  def detect_locale(""), do: @default_locale

  def detect_locale(header) when is_binary(header) do
    header
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&(String.split(&1, ";") |> List.first()))
    |> Enum.find_value(@default_locale, &normalize_locale/1)
  end

  @doc """
  Returns the locale display name.
  """
  def display_name("en"), do: gettext("English")
  def display_name("pt_BR"), do: gettext("Portuguese (BR)")
  def display_name(_), do: gettext("Unknown")

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

  defp normalize_locale(nil), do: nil

  defp normalize_locale(locale) do
    locale
    |> String.replace("-", "_")
    |> case do
      <<"pt", _::binary>> -> "pt_BR"
      <<"en", _::binary>> -> "en"
      _ -> nil
    end
  end
end
