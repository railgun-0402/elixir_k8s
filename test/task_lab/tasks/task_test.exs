defmodule TaskLab.Tasks.TaskTest do
  use ExUnit.Case, async: true

  alias TaskLab.Tasks.Task
  import TaskLab.DataCase, only: [errors_on: 1]

  describe "changeset/2" do
    test "正常なタイトルならvalid?がtrue" do
      changeset = Task.changeset(%Task{}, %{title: "牛乳を買う"})

      assert changeset.valid?
    end

    test "titleが空文字列ならvalid?がfalse" do
      changeset = Task.changeset(%Task{}, %{title: ""})

      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "titleが空白のみならvalid?がfalse" do
      changeset = Task.changeset(%Task{}, %{title: "   "})

      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "titleが256文字ならvalid?がfalse" do
      changeset = Task.changeset(%Task{}, %{title: String.duplicate("a", 256)})

      refute changeset.valid?
      assert %{title: ["should be at most 255 character(s)"]} = errors_on(changeset)
    end

    test "completedが不正な型ならvalid?がfalse" do
      changeset = Task.changeset(%Task{}, %{title: "牛乳を買う", completed: "not_a_boolean"})

      refute changeset.valid?
      assert %{completed: ["is invalid"]} = errors_on(changeset)
    end

    test "許可していないidは変更されない" do
      changeset =
        Task.changeset(%Task{}, %{
          id: 999,
          title: "牛乳を買う"
        })

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :id)
    end
  end
end
