defmodule TaskLabWeb.TaskControllerTest do
  use TaskLabWeb.ConnCase, async: true

  alias TaskLab.Tasks

  describe "GET /api/tasks" do
    test "タスクがなければ空のリストを返す", %{conn: conn} do
      conn = get(conn, ~p"/api/tasks")

      assert json_response(conn, 200) == %{"data" => []}
    end

    test "登録済みのタスクを一覧で返す", %{conn: conn} do
      {:ok, task} = Tasks.create_task(%{title: "牛乳を買う"})

      conn = get(conn, ~p"/api/tasks")

      assert json_response(conn, 200) == %{
               "data" => [%{"id" => task.id, "title" => "牛乳を買う", "completed" => false}]
             }
    end
  end

  describe "POST /api/tasks" do
    test "正常なパラメータなら201で作成したタスクを返す", %{conn: conn} do
      conn = post(conn, ~p"/api/tasks", %{title: "牛乳を買う"})

      assert %{"id" => id, "title" => "牛乳を買う", "completed" => false} =
               json_response(conn, 201)["data"]

      assert Tasks.get_task(id)
    end

    test "titleが空なら422でエラーを返し、保存しない", %{conn: conn} do
      conn = post(conn, ~p"/api/tasks", %{title: ""})

      assert json_response(conn, 422) == %{"errors" => %{"title" => ["can't be blank"]}}
      assert Tasks.list_tasks() == []
    end

    test "titleが256文字なら422でエラーを返す", %{conn: conn} do
      conn = post(conn, ~p"/api/tasks", %{title: String.duplicate("a", 256)})

      assert json_response(conn, 422) == %{
               "errors" => %{"title" => ["should be at most 255 character(s)"]}
             }
    end
  end

  describe "PATCH /api/tasks/:id/complete" do
    test "未完了のタスクなら200で完了済みのタスクを返す", %{conn: conn} do
      {:ok, task} = Tasks.create_task(%{title: "牛乳を買う"})

      conn = patch(conn, ~p"/api/tasks/#{task.id}/complete")

      assert json_response(conn, 200) == %{
               "data" => %{"id" => task.id, "title" => "牛乳を買う", "completed" => true}
             }
    end

    test "存在しないIDなら404を返す", %{conn: conn} do
      conn = patch(conn, ~p"/api/tasks/-1/complete")

      assert json_response(conn, 404) == %{"error" => "Task not found"}
    end

    test "完了済みのタスクなら409を返す", %{conn: conn} do
      {:ok, task} = Tasks.create_task(%{title: "牛乳を買う"})
      {:ok, _} = Tasks.complete_task(task.id)

      conn = patch(conn, ~p"/api/tasks/#{task.id}/complete")

      assert json_response(conn, 409) == %{"error" => "Task already completed"}
    end

    test "IDが数値でなければ400を返す", %{conn: conn} do
      assert_error_sent 400, fn ->
        patch(conn, ~p"/api/tasks/abc/complete")
      end
    end
  end
end
