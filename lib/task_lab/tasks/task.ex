defmodule TaskLab.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    field :title, :string
    field :completed, :boolean, default: false
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :completed])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 255)
  end
end
