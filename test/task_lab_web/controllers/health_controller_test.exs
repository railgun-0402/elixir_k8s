defmodule TaskLabWeb.HealthControllerTest do
  use TaskLabWeb.ConnCase, async: true

  describe "GET /health/live" do
    test "200を返す", %{conn: conn} do
      conn = get(conn, ~p"/health/live")

      assert json_response(conn, 200) == %{"status" => "ok"}
    end

    test "Acceptヘッダーがjson以外でも200を返す", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "text/plain")
        |> get(~p"/health/live")

      assert conn.status == 200
    end
  end

  describe "GET /health/ready" do
    test "DBとTaskServerが使えれば200を返す", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      assert json_response(conn, 200) == %{
               "status" => "ok",
               "checks" => %{"db" => "ok", "task_server" => "ok"}
             }
    end
  end
end
