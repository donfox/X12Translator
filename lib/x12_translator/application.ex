# Copyright (c) 2026 Don Fox
# Licensed under the MIT License. See LICENSE file in the project root.

defmodule X12Translator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      X12TranslatorWeb.Telemetry,
      X12Translator.Repo,
      {DNSCluster, query: Application.get_env(:x12_translator, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: X12Translator.PubSub},
      # Start a worker by calling: X12Translator.Worker.start_link(arg)
      # {X12Translator.Worker, arg},
      # Start to serve requests, typically the last entry
      X12TranslatorWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: X12Translator.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    X12TranslatorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
