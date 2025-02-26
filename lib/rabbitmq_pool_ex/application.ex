defmodule RabbitMQPoolEx.Application do
  @moduledoc """
  This module is responsible for supervising multiple connection pools for RabbitMQ connections.
  It handles the dynamic creation of pools based on configuration and ensures the proper handling
  of connection lifecycle events, providing robust management of connections and resources.
  """
  use Application

  @impl true
  def start(_type, args) do
    children = [
      {RabbitMQPoolEx.PoolSupervisor, args}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RabbitMQPoolEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
