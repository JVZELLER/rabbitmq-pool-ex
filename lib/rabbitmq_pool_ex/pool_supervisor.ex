defmodule RabbitMQPoolEx.PoolSupervisor do
  @moduledoc """
  A supervisor module for managing RabbitMQ connection pools using the `poolboy` library.

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
    config = [
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
    ```
  """
  use Supervisor

  @type poolboy_config :: {
          {scope :: :global | :local | :via, name :: atom()},
          worker_module: module(),
          size: non_neg_integer(),
          max_overflow: non_neg_integer(),
          strategy: :lifo | :fifo
        }

  @type config :: [rabbitmq_config: keyword(), connection_pools: [poolboy_config()]]

  @doc """
  Starts the PoolSupervisor with the provided configuration.

  This function initiates the supervisor and starts the connection pools according to the
  provided `config` parameter. If the `name` argument is provided, it will be used to register
  the supervisor process with the given name.

  ## Parameters:
  - `config` (`config()`): The configuration for RabbitMQ connection pools and RabbitMQ general settings.
  - `name` (optional, atom): The name to register the supervisor process under. Defaults to `__MODULE`.
  """
  @spec start_link(config()) :: Supervisor.on_start()
  def start_link(config), do: Supervisor.start_link(__MODULE__, config)

  @spec start_link(config(), atom()) :: Supervisor.on_start()
  def start_link(config, name), do: Supervisor.start_link(__MODULE__, config, name: name)

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
