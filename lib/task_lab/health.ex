defmodule TaskLab.Health do
  @moduledoc """
  Readinessプローブで使う依存サービスの確認。

  各関数は `:ok` か `{:error, reason}` を返す。
  kubeletのプローブ(timeoutSeconds)より短く終わるよう、どちらもタイムアウトを指定する。
  """

  alias TaskLab.{Repo, TaskServer}

  @db_timeout 1_000
  @task_server_timeout 500

  # SELECT 1 でDBに問い合わせできるかを確認
  #
  # クエリの :timeout は「接続を借りてからの実行時間」にしか効かず、
  # DBが落ちていると接続プールの待ち行列で数秒ブロックされる。
  # そのため Task で包み、待ち時間も含めた全体を @db_timeout で打ち切る。
  def check_db do
    task = Task.async(&query_db/0)

    case Task.yield(task, @db_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {:error, reason}
      nil -> {:error, :timeout}
    end
  end

  defp query_db do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", [], timeout: @db_timeout) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    # 接続できない場合などは {:error, _} ではなく例外になることがある
    e -> {:error, e}
  catch
    # Repoが起動していない場合などは exit になる。
    # Task.async はリンクしているので、ここで捕まえないと呼び出し元も落ちる
    :exit, reason -> {:error, reason}
  end

  # TaskServerが時間内に応答するかを確認
  # テストで存在しないサーバーを渡せるよう、サーバー名を引数で受け取る
  def check_task_server(server \\ TaskServer) do
    case TaskServer.ping(server, @task_server_timeout) do
      :pong ->
        :ok

      other ->
        {:error, {:unexpected_reply, other}}
    end
  catch
    :exit, reason ->
      {:error, reason}
  end
end
