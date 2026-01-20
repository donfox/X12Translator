# Copyright (c) 2026 Don Fox
# Licensed under the MIT License. See LICENSE file in the project root.

defmodule X12Bridge.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      X12BridgeWeb.Telemetry,
      X12Bridge.Repo,
      {DNSCluster, query: Application.get_env(:x12_bridge, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: X12Bridge.PubSub},
      # Start a worker by calling: X12Bridge.Worker.start_link(arg)
      # {X12Bridge.Worker, arg},
      # Start to serve requests, typically the last entry
      X12BridgeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: X12Bridge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    X12BridgeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
