defmodule X12BridgeWeb.PageControllerTest do
  use X12BridgeWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Convert complex X12 EDI healthcare transactions"
  end
end
