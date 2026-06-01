defmodule RapidToolsWeb.ToolSidebarTest do
  use RapidToolsWeb.ConnCase, async: true

  test "sidebar nav has a stable id for JavaScript search hook", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "nav#tool-nav")
    assert has_element?(view, "#tool-nav[data-nav=\"tools\"]")
  end

  test "sidebar search input exists", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#tool-search input")
  end
end
