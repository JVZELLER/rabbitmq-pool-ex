defmodule RabbitmqPoolEx.PoolSupervisor do
  use Supervisor

  @type pool_boy_config :: {
          {scope :: :global | :local | :via, name :: atom()},
          worker_module: module(),
          size: non_neg_integer(),
          max_overflow: non_neg_integer(),
          strategy: :lifo | :fifo
        }
  @type config :: [rabbitmq_config: keyword(), connection_pools: [pool_boy_config()]]

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
    children =
      for pool_config <- Keyword.get(config, :connection_pools, []) do
        rabbitmq_config = Keyword.get(config, :rabbitmq_config, [])
        {_registration_scope, pool_id} = Keyword.fetch!(pool_config, :name)

        # We are using poolboy's pool as a fifo queue so we can distribute the
        # load between workers
        pool_config = Keyword.merge(pool_config, strategy: :fifo)
        :poolboy.child_spec(pool_id, pool_config, rabbitmq_config)
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
