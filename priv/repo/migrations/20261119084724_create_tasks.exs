defmodule TaskLab.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :title, :string, null: false
      add :completed, :boolean, default: false, null: false
    end
  end
end
