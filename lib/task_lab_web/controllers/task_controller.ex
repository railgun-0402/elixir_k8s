defmodule TaskLabWeb.TaskController do
  use TaskLabWeb, :controller

  alias TaskLab.Tasks

  # GET /api/tasks
  def index(conn, _params) do
    tasks = Tasks.list_tasks()

    # tasksをJSONとして返す
    json(conn, %{data: Enum.map(tasks, &task_json/1)})
  end

  # POST /api/tasks
  def create(conn, params) do
    case Tasks.create_task(params) do
      {:ok, task} ->
        # 201 Createdを返す
        conn
        |> put_status(:created)
        |> json(%{data: task_json(task)})

      {:error, changeset} ->
        # 422 Unprocessable Entityを返す
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: changeset_errors(changeset)})
    end
  end

  def complete(conn, %{"id" => id}) do
    case Tasks.complete_task(id) do
      {:ok, task} ->
        # 200を返す
        conn
        |> put_status(:ok)
        |> json(%{data: task_json(task)})

      {:error, :not_found} ->
        # 404を返す
        conn
        |> put_status(:not_found)
        |> json(%{error: "Task not found"})

      {:error, :already_completed} ->
        # 409を返す
        conn
        |> put_status(:conflict)
        |> json(%{error: "Task already completed"})
    end
  end

  # 構造体 → JSONにできるマップ
  defp task_json(task) do
    %{id: task.id, title: task.title, completed: task.completed}
  end

  # changesetのエラー → %{title: ["can't be blank"]} のようなマップ
  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r/%{(\w+)}/, msg, fn _, key ->
        opts
        |> Keyword.get(String.to_existing_atom(key), key)
        |> to_string()
      end)
    end)
  end
end
