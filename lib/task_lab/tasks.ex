defmodule TaskLab.Tasks do
  import Ecto.Query

  alias TaskLab.Repo
  alias TaskLab.Tasks.Task

  # 全タスクの取得
  def list_tasks do
    Repo.all(Task)
  end

  # IDによる取得
  def get_task(id) do
    Repo.get(Task, id)
  end

  # タスク新規作成
  def create_task(attrs) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  # タスクを完了
  # 「未完了なら完了にする」を1本のUPDATE文で行うことで、
  # 同時リクエストでも成功するのは1つだけになる
  def complete_task(id) do
    query =
      from t in Task,
        where: t.id == ^id and t.completed == false,
        select: t

    case Repo.update_all(query, set: [completed: true]) do
      {1, [task]} ->
        {:ok, task}

      {0, []} ->
        # 更新できなかった理由を判定する
        case Repo.get(Task, id) do
          nil -> {:error, :not_found}
          %Task{} -> {:error, :already_completed}
        end
    end
  end
end
