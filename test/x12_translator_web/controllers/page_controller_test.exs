defmodule X12TranslatorWeb.PageControllerTest do
  use X12TranslatorWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Convert complex X12 EDI healthcare transactions"
  end
end
