defmodule RabbitMQPoolEx.Application do
  @moduledoc """
  This module is responsible for supervising multiple connection pools for RabbitMQ connections.
  It handles the dynamic creation of pools based on configuration and ensures the proper handling
  of connection lifecycle events, providing robust management of connections and resources.

  ## Configuration

  The supervisor accepts the following configuration options:

  - `:rabbitmq_config` (keyword): General configuration for RabbitMQ connections, such as connection parameters.
  - `:connection_pools` (list): A list of poolboy configuration maps, each representing an individual connection pool.
    Each pool configuration must include:
    - `:name` (atom): The unique name for the pool.
    - `:worker_module` (module): The module responsible for managing the workers in the pool.
    - `:size` (integer): The number of worker processes in the pool.
    - `:max_overflow` (integer): The maximum number of workers that can be created above the pool's size.
    - `:strategy` (atom, either `:lifo` or `:fifo`): The strategy used by the pool to manage the order of worker allocation. Defaults to `:fifo`

  ## Example Configuration:
    ```elixir
    defmodule MyApp.Application do
      @moduledoc false

      @impl true
      def start(_type, _args) do
        children = [
          {RabbitMQPoolEx.Application, get_pool_config()}
        ]

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

      defp get_pool_config do
        [
          rabbitmq_config: [host: "localhost", port: 5672, reuse_channels: true, channels: 20],
          connection_pools: [
            %{
              name: :default_pool,
              worker_module: RabbitMQPoolEx.Worker,
              size: 5,
              max_overflow: 2,
              strategy: :lifo
            }
          ]
        ]
      end
    end
    ```
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
      rabbitmq_config = Keyword.get(config, :rabbitmq_config, [])
      {_registration_scope, pool_id} = Keyword.fetch!(pool_config, :name)

      # We are using poolboy's pool as a fifo queue so we can distribute the
      # load between workers
      pool_config = Keyword.merge(pool_config, strategy: :fifo)
      :poolboy.child_spec(pool_id, pool_config, rabbitmq_config)
    end
  end
end
