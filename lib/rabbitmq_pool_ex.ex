defmodule RabbitMQPoolEx do
  @moduledoc """
  `RabbitMQPoolEx` is an Elixir library that provides a robust and efficient connection pooling mechanism for RabbitMQ.
  It leverages `poolboy` to manage a pool of connections, ensuring high performance and reliability in message-driven
  applications.

  ## Features

  - **Connection Pooling**: Efficiently manage multiple RabbitMQ connections to handle high-throughput messaging.
  - **Channel Management**: Simplify the process of acquiring and releasing channels from the connection pool.
  - **Fault Tolerance**: Automatically handle connection drops and retries, ensuring minimal disruption to message
    processing.
  - **Channel Reuse**: Optionally reuse channels within a pool to optimize resource management.
  - **Configurable Pooling Strategy**: Customize the size, overflow, and behavior of connection pools.
  - **Pool Metrics**: Built-in telemetry metrics for monitoring pools.

  ## Installation

  To integrate `RabbitMQPoolEx` into your project, add the following to your `mix.exs` dependencies:

  ```elixir
  defp deps do
    [
      {:rabbitmq_pool_ex, "~> 1.0.0"}
    ]
  end
  ```

  Then, fetch and install the dependencies by running:

  ```sh
  mix deps.get
  ```

  ## Configuration

  `RabbitMQPoolEx` requires defining connection pools and RabbitMQ settings. The configuration consists of:

  - `:rabbitmq_config` (keyword list) – General RabbitMQ connection parameters.
    All `rabbitmq_config` options goes directly to RabbitMQ client (`AMQP`) to open the connection with the RabbitMQ broker.

  - `:connection_pools` (list) – A list of poolboy configurations, where each pool represents a connection to RabbitMQ.

  Each pool configuration should include:

  - `:name` (tuple) – Required. A two element tuple containing the process registration scope and an unique name for the pool (e.g., {:local, :default_pool}).
  - `:worker_module` (module) – Optional. Defaults to `RabbitMQPoolEx.Worker.RabbitMQConnection`, which manages pool connections and channels.
  - `:size` (integer) – Required. Number of connection processes in the pool.
  - `:channels` (integer) – Required. Number of channels managed within the pool.
  - `:reuse_channels?` (boolean) – Optional. Defaults to `false`. Determines if channels should be reused instead of replaced after being used.
  - `:max_overflow` (integer) – Required. Maximum number of extra connections allowed beyond the initial pool size.

  ### Example Configuration

  <!-- tabs-open -->

  ### Basic configuration

  To use `RabbitMQPoolEx`, add the following to your application's supervision tree:

  ```elixir
  defmodule MyApp.Application do
    @moduledoc false

    @impl true
    def start(_type, _args) do
      children = [
        {RabbitMQPoolEx.PoolSupervisor, get_pool_config()}
      ]

      opts = [strategy: :one_for_one, name: MyApp.Supervisor]
      Supervisor.start_link(children, opts)
    end

    defp get_pool_config do
      pool_size = 10

      [
        rabbitmq_config: [host: "localhost", port: 5672],
        connection_pools:
          Enum.map(1..pool_size, fn n ->
            [
              name: {:local, String.to_atom("connection_pool_\#{n}")},
              size: 5,
              channels: 20,
              reuse_channels?: true,
              max_overflow: 2
            ]
          end)
      ]
    end
  end
  ```

  ### Custom RabbitMQ connection opts

  To use `RabbitMQPoolEx`, add the following to your application's supervision tree:

  ```elixir
  defmodule MyApp.Application do
    @moduledoc false

    @impl true
    def start(_type, _args) do
      children = [
        {RabbitMQPoolEx.PoolSupervisor, get_pool_config()}
      ]

      opts = [strategy: :one_for_one, name: MyApp.Supervisor]
      Supervisor.start_link(children, opts)
    end

    defp get_pool_config do
      [
        rabbitmq_config: [
          host: "localhost",
          port: 5672,
          # Optional. Enables SSL.
          # See `AMQP.Connection.open/2` for more information
          ssl_options: [
            verify: :verify_peer,
            cacertfile: "/path/to/cacertfile",
            depth: 3,
            customize_hostname_check: [
              match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
            ]
          ]
        ],
        connection_pools: [
          [
            name: {:local, :ssl_pool},
            size: 5,
            channels: 20,
            reuse_channels?: true,
            max_overflow: 2
          ]
        ]
      ]
    end
  end
  ```

  <!-- tabs-close -->

  ### Visual representation

  Given a configuration with two pools, where each pool has:
  - `size: 2` - two connections per pool
  - `channels: 2` - each connection manages two channels

  The resulting topology would be as follows::
  ```mermaid
  graph TD
    pool_1@{ shape: dbl-circ, label: "connection_pool_1" }
    pool_2@{ shape: dbl-circ, label: "connection_pool_2" }

    conn_1_pool_1@{ shape: circle, label: "Connection n 1" }
    conn_2_pool_1@{ shape: circle, label: "Connection n 2" }
    conn_1_pool_2@{ shape: circle, label: "Connection n 1" }
    conn_2_pool_2@{ shape: circle, label: "Connection n 2" }

    pool_1_conn_1_channel_1@{ shape: circle, label: "Channel n 1" }
    pool_1_conn_1_channel_2@{ shape: circle, label: "Channel n 2" }
    pool_1_conn_2_channel_1@{ shape: circle, label: "Channel n 1" }
    pool_1_conn_2_channel_2@{ shape: circle, label: "Channel n 2" }

    pool_2_conn_1_channel_1@{ shape: circle, label: "Channel n 1" }
    pool_2_conn_1_channel_2@{ shape: circle, label: "Channel n 2" }
    pool_2_conn_2_channel_1@{ shape: circle, label: "Channel n 1" }
    pool_2_conn_2_channel_2@{ shape: circle, label: "Channel n 2" }

    pool_1 --- conn_1_pool_1 & conn_2_pool_1;
    pool_2 --- conn_1_pool_2 & conn_2_pool_2;

    conn_1_pool_1 --> pool_1_conn_1_channel_1 & pool_1_conn_1_channel_2;
    conn_2_pool_1 --> pool_1_conn_2_channel_1 & pool_1_conn_2_channel_2;

    conn_1_pool_2 --> pool_2_conn_1_channel_1 & pool_2_conn_1_channel_2;
    conn_2_pool_2 --> pool_2_conn_2_channel_1 & pool_2_conn_2_channel_2;
  ```

  ## Usage

  Once configured, you can interact with RabbitMQ through the pooled connections. Here's how to publish a message:

  ```elixir
  RabbitMQPoolEx.with_channel(:rabbitmq_pool, fn
    {:ok, channel} ->
      AMQP.Basic.publish(channel, "exchange_name", "routing_key", "Hello, World!")
      :ok
    {:error, reason} ->
      IO.puts("Failed to acquire channel", error: inspect(reason))
  end)
  ```

  In this example, `with_channel/2` checks out a channel from the pool, executes the given function, and ensures the
  channel is returned to the pool afterward.

  For more advanced usage, such as setting up consumers or handling different exchange types, refer to the detailed
  documentation and examples provided in the library's repository.

  ### Manually retrieving a connection

  To manually retrieve a RabbitMQ connection from the pool:

  ```elixir
  {:ok, conn} = RabbitMQPoolEx.get_connection(:default_pool)
  ```

  ### Manually checking out and checking in a channel

  ```elixir
  {:ok, channel} = RabbitMQPoolEx.checkout_channel(worker_pid)

  # Perform operations...

  RabbitMQPoolEx.checkin_channel(worker_pid, channel)
  ```

  In the example above, `checkout_channel/1` retrieves a RabbitMQ channel from the connection worker,
  and `checkin_channel/2` returns it to the pool when done.

  ## Telemetry

  > #### Metrics declaration {: .info}
  >
  > All metrics are defined in specific modules so you can use them like this: `RabbitMQPoolEx.Telemetry.Metrics.PoolSize.metrics()`
  > in your telemetry supervisor.
  >
  > Check the **"Telemetry Metrics"** section in the sidebar for a list of all available modules.

  `RabbitMQPoolEx` currently exposes following Telemetry events:

    * `[:rabbitmq_pool_ex, :metrics, :pool_size]` - Dispatched whenever an operation increases or
      decreases the pool size.

      * Measurement: `%{count: integer}`
      * Metadata:

        ```elixir
        %{
          pool_id: atom,
          channels_count: non_neg_integer,
          reuse_channels: boolean,
        }
        ```
        Check `RabbitMQPoolEx.Telemetry.Metrics.PoolSize` for more information.

  ## License

  RabbitMQPoolEx is released under the Apache 2.0 License.
  """

  alias RabbitMQPoolEx.Worker.RabbitMQConnection, as: Conn

  @typedoc """
  The function to be used with `with_channel/2`
  """

  @type client_function ::
          ({:ok, AMQP.Channel.t()} | {:error, :disconnected | :out_of_channels} -> any())

  @doc """
  Retrieves a RabbitMQ connection from a connection worker within the pool.

  ## Parameters
    - `pool_id`: Atom representing the pool identifier.
  """
  @spec get_connection(atom()) :: {:ok, AMQP.Connection.t()} | {:error, :disconnected}
  def get_connection(pool_id) do
    :poolboy.transaction(pool_id, &Conn.get_connection/1)
  end

  @doc """
  Retrieves a connection worker from the pool.

  This function uses the pool for load distribution and does not isolate access to individual workers.
  The pool configuration strategy is FIFO.

  ## Parameters
    - `pool_id:` Atom representing the pool identifier.
  """
  @spec get_connection_worker(atom()) :: pid()
  def get_connection_worker(pool_id) do
    conn_worker = :poolboy.checkout(pool_id)
    :ok = :poolboy.checkin(pool_id, conn_worker)
    conn_worker
  end

  @doc """
  Executes a given function within the context of a RabbitMQ channel.

  This function:
    1. Retrieves the reference (pid) of connection worker from the pool and
      immediately put it back into the pool, so any other concurrent client
      can have access to it.
    2. Obtains a RabbitMQ channel from that worker.
    3. Executes the provided function using the channel.
    4. Returns the channel to the worker's pool.

  ## Parameters
    - `pool_id`: Atom representing the pool identifier.
    - `fun`: Function to be executed within the channel's context.
  """
  @spec with_channel(atom(), client_function()) :: any()
  def with_channel(pool_id, fun) do
    pool_id
    |> get_connection_worker()
    |> do_with_conn(fun)
  end

  @doc """
  Retrieves a RabbitMQ channel from the specified connection worker.

  ## Parameters
    - `conn_worker`: PID of the connection worker.
  """
  @spec checkout_channel(pid()) ::
          {:ok, AMQP.Channel.t()} | {:error, :disconnected | :out_of_channels}
  def checkout_channel(conn_worker) do
    Conn.checkout_channel(conn_worker)
  end

  @doc """
  Returns a RabbitMQ channel to its corresponding connection worker.

  ## Parameters
    - `conn_worker`: PID of the connection worker.
    - `channel`: The RabbitMQ channel to be returned.
  """
  @spec checkin_channel(pid(), AMQP.Channel.t()) :: :ok
  def checkin_channel(conn_worker, channel) do
    Conn.checkin_channel(conn_worker, channel)
  end

  # Gets a channel out of a connection worker and performs a function with it
  # then it puts it back to the same connection worker, mimicking a transaction.
  @spec do_with_conn(pid(), client_function()) :: any()
  defp do_with_conn(conn_worker, fun) do
    case checkout_channel(conn_worker) do
      {:ok, channel} = ok_chan ->
        try do
          fun.(ok_chan)
        after
          :ok = checkin_channel(conn_worker, channel)
        end

      {:error, _} = error ->
        fun.(error)
    end
  end
end
