defmodule RapidToolsWeb.PageController do
  use RapidToolsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
