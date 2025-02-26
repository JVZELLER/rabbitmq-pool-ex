defmodule RabbitMQPoolEx.Worker.State do
  @moduledoc """
  Represents the state of the RabbitMQ connection worker.

  ## Fields

    * `:connection` - The active RabbitMQ connection.
    * `:channels` - List of channels available in the pool.
    * `:monitors` - Map of monitored processes holding channels.
    * `:config` - Configuration options provided when starting the worker.
    * `:reuse_channels?` - Boolean indicating if channels are reused.
  """

  alias RabbitMQPoolEx.Adapters.RabbitMQ

  @type config :: keyword() | String.t()

  @enforce_keys [:config]
  @type t :: %__MODULE__{
          adapter: module(),
          connection: AMQP.Connection.t(),
          channels: list(AMQP.Channel.t()),
          monitors: %{},
          config: config(),
          reuse_channels?: boolean()
        }

  defstruct adapter: RabbitMQ,
            connection: nil,
            channels: [],
            config: nil,
            monitors: %{},
            reuse_channels?: false
end
