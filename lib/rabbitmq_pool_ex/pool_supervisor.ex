defmodule RabbitMQPoolEx.PoolSupervisor do
  @moduledoc false

  use Supervisor

  alias RabbitMQPoolEx.Worker.RabbitMQConnection

  @type config :: [rabbitmq_config: keyword(), connection_pools: list()]

  @spec start_link(config()) :: Supervisor.on_start()
  def start_link(config) do
    Supervisor.start_link(__MODULE__, config)
  end

  @spec start_link(config(), atom()) :: Supervisor.on_start()
  def start_link(config, name) do
    Supervisor.start_link(__MODULE__, config, name: name)
  end

  @impl true
  def init(config) do
    children = poolboy_children(config)

    opts = [strategy: :one_for_one]

    Supervisor.init(children, opts)
  end

  defp poolboy_children(config) do
    for pool_config <- Keyword.get(config, :connection_pools, []) do
      {_registration_scope, pool_id} = Keyword.fetch!(pool_config, :name)

      {channels_config, poolboy_config} =
        Keyword.split(pool_config, ~w(channels reuse_channels?)a)

      worker_config =
        config
        |> Keyword.get(:rabbitmq_config, [])
        |> Keyword.merge(channels_config)
        |> Keyword.put(:pool_id, pool_id)

      # We are using poolboy's pool as a fifo queue so we can distribute the
      # load between workers
      poolboy_config =
        Keyword.merge(poolboy_config, worker_module: RabbitMQConnection, strategy: :fifo)

      :poolboy.child_spec(pool_id, poolboy_config, worker_config)
    end
  end
end
