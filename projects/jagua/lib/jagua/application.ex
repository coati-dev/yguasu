defmodule Jagua.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JaguaWeb.Telemetry,
      Jagua.Repo,
      {DNSCluster, query: Application.get_env(:jagua, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Jagua.PubSub},
      {Finch, name: Jagua.Finch},
      Jagua.RateLimiter,
      {Registry, keys: :unique, name: Jagua.Sentinel.Registry},
      {DynamicSupervisor, name: Jagua.Sentinel.Supervisor, strategy: :one_for_one},
      Jagua.Sentinel.Loader,
      JaguaWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Jagua.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JaguaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
