defmodule TaskLab.TasksTest do
  use TaskLab.DataCase, async: true

  alias TaskLab.Tasks
  alias TaskLab.Tasks.Task

  describe "complete_task/1" do
    test "未完了のタスクを完了にできる" do
      {:ok, task} = Tasks.create_task(%{title: "牛乳を買う"})

      assert {:ok, %Task{id: id, completed: true}} = Tasks.complete_task(task.id)
      assert id == task.id
      assert %Task{completed: true} = Tasks.get_task(task.id)
    end

    test "存在しないIDなら{:error, :not_found}" do
      assert {:error, :not_found} = Tasks.complete_task(-1)
    end

    test "完了済みのタスクなら{:error, :already_completed}" do
      {:ok, task} = Tasks.create_task(%{title: "牛乳を買う"})
      {:ok, _} = Tasks.complete_task(task.id)

      assert {:error, :already_completed} = Tasks.complete_task(task.id)
    end
  end
end
