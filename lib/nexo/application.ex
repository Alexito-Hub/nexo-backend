defmodule Nexo.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      NexoWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:nexo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Nexo.PubSub},
      {Mongo, [name: :mongo, url: Nexo.Db.url(), pool_size: 5, ssl_opts: Nexo.Db.ssl_opts()]},
      # Start to serve requests, typically the last entry
      NexoWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Nexo.Supervisor]
    result = Supervisor.start_link(children, opts)
    Nexo.Db.ensure_indexes_async()
    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NexoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
