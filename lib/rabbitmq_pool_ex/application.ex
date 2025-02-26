defmodule RabbitMQPoolEx.Application do
  @moduledoc """
  This module is responsible for supervising multiple connection pools for RabbitMQ connections.
  It handles the dynamic creation of pools based on configuration and ensures the proper handling
  of connection lifecycle events, providing robust management of connections and resources.
  """
  use Application

  @impl true
  def start(_type, args) do
    children = poolboy_children(args)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RabbitMQPoolEx.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp poolboy_children(config) do
    for pool_config <- Keyword.get(config, :connection_pools, []) do
      {_registration_scope, pool_id} = Keyword.fetch!(pool_config, :name)

      {channels_config, poolboy_config} =
        Keyword.split(pool_config, ~w(channels reuse_channels?)a)

      rabbitmq_config =
        config |> Keyword.get(:rabbitmq_config, []) |> Keyword.merge(channels_config)

      # We are using poolboy's pool as a fifo queue so we can distribute the
      # load between workers
      poolboy_config =
        Keyword.merge(poolboy_config, worker_module: RabbitMQConnection, strategy: :fifo)

      :poolboy.child_spec(pool_id, poolboy_config, rabbitmq_config)
    end
  end
end
