defmodule RabbitMQPoolEx.Adapters.RabbitMQ do
  @moduledoc """
  The default adapter for interacting with RabbitMQ using the `AMQP` library.

  This module implements the `RabbitMQPoolEx.Ports.RabbitMQ` behavior, providing concrete implementations
  that delegate directly to the `AMQP.Connection` and `AMQP.Channel` modules.
  """

  alias AMQP.Connection
  alias AMQP.Channel

  @behaviour RabbitMQPoolEx.Ports.RabbitMQ

  defdelegate open_connection(config), to: Connection, as: :open

  defdelegate close_connection(config), to: Connection, as: :close

  defdelegate open_channel, to: Channel, as: :open

  defdelegate close_channel, to: Channel, as: :close
end
