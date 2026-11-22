defmodule TaskLab.TaskServer do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, 0, name: __MODULE__)
  end

  @impl true
  def init(initial_count) do
    {:ok, initial_count}
  end

  def increment do
    GenServer.call(__MODULE__, :increment)
  end

  def count do
    GenServer.call(__MODULE__, :count)
  end

  # ヘルスチェック用。状態は変えずに応答だけ返す
  def ping(server \\ __MODULE__, timeout \\ 5_000) do
    GenServer.call(server, :ping, timeout)
  end

  @impl true
  def handle_call(:increment, _from, count) do
    new_count = count + 1
    {:reply, new_count, new_count}
  end

  @impl true
  def handle_call(:count, _from, count) do
    {:reply, count, count}
  end

  def handle_call(:ping, _from, count) do
    {:reply, :pong, count}
  end
end
