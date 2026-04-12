defmodule Jagua.Tasks do
  @moduledoc """
  Fire-and-forget task helper with test sandbox support.

  In production, `start/1` spawns the work in a background task so it
  doesn't block the caller.  In test mode (`config :jagua, async_tasks:
  false`), it runs synchronously so the work completes before the Ecto
  sandbox is torn down, avoiding connection-leak log noise.
  """

  @doc """
  Runs `fun` in a background task, or synchronously in test mode.

  In async mode the spawned task:
  - calls `Ecto.Adapters.SQL.Sandbox.allow/3` so it inherits the
    caller's sandbox connection (required when the sandbox pool is in
    non-shared / manual mode)
  - catches `:exit` to handle the edge case where the sandbox owner
    exits before the task can check out a connection
  """
  def start(fun) do
    if Application.get_env(:jagua, :async_tasks, true) do
      caller = self()

      Task.start(fn ->
        try do
          Ecto.Adapters.SQL.Sandbox.allow(Jagua.Repo, caller, self())
          fun.()
        catch
          :exit, _ -> :ok
        end
      end)
    else
      fun.()
      {:ok, self()}
    end
  end
end
