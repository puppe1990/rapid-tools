defmodule RapidToolsWeb.LocaleTest do
  use ExUnit.Case, async: true

  alias RapidToolsWeb.Locale

  test "display_name is translated using the current gettext locale" do
    Gettext.put_locale(RapidToolsWeb.Gettext, "pt_BR")
    assert Locale.display_name("en") == "Inglês"

    Gettext.put_locale(RapidToolsWeb.Gettext, "en")
    assert Locale.display_name("pt_BR") == "Portuguese (BR)"
  end
end
