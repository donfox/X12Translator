defmodule X12TranslatorWeb.PageController do
  use X12TranslatorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
