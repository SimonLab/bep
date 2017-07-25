defmodule Bep.ConsentControllerTest do
  use Bep.ConnCase
  setup %{conn: conn} = config do
    if user = config[:login_as] do
      conn = assign(conn, :current_user, user)
      {:ok, conn: conn, user: user}
    else
      :ok
    end
  end

  test "GET /", %{conn: conn} do
    conn = get conn, "/consent"
    assert html_response(conn, 200) =~ "I understand that data entered may be used for reasearch"
  end

  @tag login_as: %{email: "email@example.com"}
  test "GET / redirect to /search when logged in", %{conn: conn} do
    conn = get conn, "/consent"
    assert html_response(conn, 302)
  end
end
