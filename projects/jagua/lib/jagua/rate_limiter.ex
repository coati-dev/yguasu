defmodule Jagua.RateLimiter do
  @moduledoc """
  Simple ETS-based fixed-window rate limiter.

  Uses an ETS table keyed by {bucket_type, identifier, window_id} where
  window_id = div(unix_timestamp, window_seconds). No cleanup needed — old
  keys are just stale entries that will never match again.

  Started as part of the application supervision tree.
  """

  use GenServer

  @table :jagua_rate_limiter

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])
    # Periodically clean up old windows
    Process.send_after(self(), :cleanup, :timer.minutes(10))
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.system_time(:second)
    # Remove entries older than 1 hour
    cutoff = div(now, 60) - 60
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    Process.send_after(self(), :cleanup, :timer.minutes(10))
    {:noreply, state}
  end

  @doc """
  Check if the request should be allowed.
  Returns :ok or {:error, :rate_limited}.

  - type: atom identifying the bucket type (e.g. :check_in, :api)
  - key: string identifier (token, key_id, etc.)
  - limit: max requests per window
  - window_seconds: window size in seconds
  """
  def check(type, key, limit, window_seconds) do
    now = System.system_time(:second)
    window_id = div(now, window_seconds)
    ets_key = {type, key, window_id}

    count = :ets.update_counter(@table, ets_key, {2, 1}, {ets_key, 0})

    if count <= limit do
      :ok
    else
      {:error, :rate_limited}
    end
  end
end
