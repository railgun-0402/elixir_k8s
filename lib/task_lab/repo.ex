defmodule TaskLab.Repo do
  use Ecto.Repo,
    otp_app: :task_lab,
    adapter: Ecto.Adapters.Postgres
end
