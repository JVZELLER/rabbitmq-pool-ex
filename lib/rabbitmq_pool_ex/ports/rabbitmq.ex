defmodule RabbitMQPoolEx.Ports.RabbitMQ do
  @moduledoc """
  A behavior module defining the contract for interacting with RabbitMQ connections and channels.

  This module acts as a port, abstracting the interaction with the RabbitMQ server using the `AMQP` library.
  It provides callbacks that define the expected behavior for opening and closing both connections and channels.

  Implementations of this module should adhere to these callbacks to ensure consistent communication with RabbitMQ.

  ## Callbacks

  - `c:open_connection/1`:
    Opens a connection to the RabbitMQ server using either a keyword list or a connection string.
    Returns `{:ok, Connection.t()}` on success or `{:error, reason}` on failure.

  - `c:close_connection/1`:
    Closes an active RabbitMQ connection.
    Returns `:ok` on success or `{:error, reason}` on failure.

  - `c:open_channel/1`:
    Opens a new channel within an existing RabbitMQ connection.
    Returns `{:ok, Channel.t()}` on success or `{:error, reason}` on failure.

  - `c:close_channel/1`:
    Closes an active RabbitMQ channel.
    Returns `:ok` on success or `{:error, AMQP.Basic.error()}` on failure.

  ## Example

  To implement this behavior in a module:
  ```elixir
    defmodule MyApp.RabbitMQ do
      @behaviour RabbitMQPoolEx.Ports.RabbitMQ

      def open_connection(config) do
        AMQP.Connection.open(config)
      end

      def close_connection(connection) do
        AMQP.Connection.close(connection)
      end

      def open_channel(connection) do
        AMQP.Channel.open(connection)
      end

      def close_channel(channel) do
        AMQP.Channel.close(channel)
      end
    end
  ```

  This design allows for easy mocking and testing by providing alternative implementations as needed.
  """

  alias AMQP.Connection
  alias AMQP.Channel

  @callback open_connection(keyword() | String.t()) ::
              {:ok, Connection.t()} | {:error, atom()} | {:error, any()}

  @callback close_connection(Connection.t()) :: :ok | {:error, any()}

  @callback open_channel(Connection.t()) :: {:ok, Channel.t()} | {:error, any()}

  @callback close_channel(Channel.t()) :: :ok | {:error, AMQP.Basic.error()}
end
