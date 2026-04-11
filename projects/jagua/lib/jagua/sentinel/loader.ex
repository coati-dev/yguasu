defmodule Jagua.Sentinel.Loader do
  @moduledoc """
  Starts a Timer GenServer for every active (non-paused) sentinel on application boot.
  Re-runs after a short delay to handle any sentinels that were in-flight during startup.
  """

  use GenServer, restart: :permanent

  require Logger

  def start_link(_opts) do
    if Application.get_env(:jagua, :sentinel_loader_enabled, true) do
      GenServer.start_link(__MODULE__, [], name: __MODULE__)
    else
      :ignore
    end
  end

  @impl true
  def init(_) do
    # Schedule the load after the Repo is ready
    Process.send_after(self(), :load, 1_000)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:load, state) do
    load_active_sentinels()
    {:noreply, state}
  end

  defp load_active_sentinels do
    sentinels =
      Jagua.Sentinels.Sentinel
      |> Ash.Query.for_read(:active)
      |> Ash.read!(domain: Jagua.Sentinels)

    Enum.each(sentinels, &Jagua.Sentinel.Timer.ensure_started/1)

    Logger.info("Jagua.Sentinel.Loader: started timers for #{length(sentinels)} sentinel(s)")
  end
end
