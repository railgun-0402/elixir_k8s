defmodule TaskLabWeb.HealthController do
  use TaskLabWeb, :controller

  require Logger

  alias TaskLab.Health

  # DB,TaskServerどちらも見ない・応答できること = BEAMとEndpointが生きてる
  # Livenessが失敗すると、kubeletはコンテナを再起動
  # DBが落ちた時に全Podが再起動を繰り返しても、DBは治らないので
  def live(conn, _params) do
    # HTTP リクエストを処理できたら200
    json(conn, %{status: "ok"})
  end

  # 依存サービスが使えるか = このPodにリクエストを送っていいか
  def ready(conn, _params) do
    checks = %{db: Health.check_db(), task_server: Health.check_task_server()}

    # すべて :ok なら200、1つでも失敗なら503
    if Enum.all?(checks, fn {_name, result} -> result == :ok end) do
      json(conn, %{status: "ok", checks: format(checks)})
    else
      Logger.warning("readiness check failed: #{inspect(checks)}")

      conn
      |> put_status(:service_unavailable)
      |> json(%{status: "error", checks: format(checks)})
    end
  end

  # %{db: :ok, task_server: {:error, ...}} → %{db: "ok", task_server: "error"}
  # 例外の中身はレスポンスに出さず、ログにだけ出す
  defp format(checks) do
    Map.new(checks, fn
      {name, :ok} -> {name, "ok"}
      {name, {:error, _reason}} -> {name, "error"}
    end)
  end
end
