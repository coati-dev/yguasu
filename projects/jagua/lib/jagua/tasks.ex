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

  In production (`async_tasks: true`, the default) the work is spawned
  in a separate process so it doesn't block the caller. In test mode
  (`config :jagua, async_tasks: false`) it runs synchronously so the
  work completes before the Ecto sandbox is torn down.
  """
  def start(fun) do
    if Application.get_env(:jagua, :async_tasks, true) do
      Task.start(fun)
    else
      fun.()
      {:ok, self()}
    end
  end
end
