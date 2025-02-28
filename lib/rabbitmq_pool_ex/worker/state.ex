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
          pool_id: atom(),
          adapter: module(),
          connection: AMQP.Connection.t(),
          channels: list(AMQP.Channel.t()),
          channels_count: non_neg_integer(),
          pool_size: non_neg_integer(),
          monitors: %{},
          config: config(),
          reuse_channels?: boolean()
        }

  defstruct pool_id: nil,
            adapter: RabbitMQ,
            connection: nil,
            channels: [],
            channels_count: nil,
            pool_size: nil,
            config: nil,
            monitors: %{},
            reuse_channels?: false
end
