defmodule TaskLab.HealthTest do
  use TaskLab.DataCase, async: true

  alias TaskLab.Health

  describe "check_db/0" do
    test "DBに問い合わせできれば:ok" do
      assert Health.check_db() == :ok
    end
  end

  describe "check_task_server/1" do
    test "TaskServerが応答すれば:ok" do
      assert Health.check_task_server() == :ok
    end

    test "サーバーが存在しなければ{:error, _}" do
      assert {:error, _reason} = Health.check_task_server(:no_such_server)
    end

    test "サーバーが時間内に応答しなければ{:error, _}" do
      # メッセージを受け取っても返事をしないプロセス
      pid = start_supervised!({Task, fn -> Process.sleep(:infinity) end})

      assert {:error, {:timeout, _}} = Health.check_task_server(pid)
    end
  end
end
