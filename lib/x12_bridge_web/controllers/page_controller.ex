defmodule X12BridgeWeb.PageController do
  use X12BridgeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
