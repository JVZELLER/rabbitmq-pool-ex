defmodule RabbitMQPoolEx.Telemetry.Metrics.PoolSize do
  @moduledoc """
  Telemetry metrics for monitoring the pool size of RabbitMQ connections.

  This module defines telemetry metrics related to the size of the connection pool in `RabbitMQPoolEx`.
  It provides a metric for tracking the last known pool size and emits telemetry events when the pool size changes.
  """
  alias RabbitMQPoolEx.Worker.State
  alias Telemetry.Metrics

  @measurement :count
  @metric_name ~w(rabbitmq_pool_ex metrics pool_size #{@measurement})a
  @telemetry_event @metric_name -- [@measurement]
  @tags ~w(pool_id channels_count reuse_channels)a

  @doc """
  Returns a list of telemetry metrics for monitoring the RabbitMQ connection pool size.

  This function defines the following metric:

  - `rabbitmq_pool_ex.metrics.pool_size.count`: Tracks the latest pool size value.

  ## Metadata

  The event includes the following metadata as tags:

  - `:pool_id` - The identifier of the connection pool.
  - `:channels_count` - The number of active channels in the connection.
  - `:reuse_channels` - Whether channels are being reused.
  """
  @spec metrics() :: list(Telemetry.Metrics.t())
  def metrics do
    [
      Metrics.last_value(@metric_name,
        tags: @tags,
        description: "Tracks the latest pool size value."
      )
    ]
  end

  @doc false
  @spec execute(State.t()) :: :ok
  def execute(%{pool_size: count, reuse_channels?: reuse_channels} = state) do
    tags = state |> Map.take(@tags) |> Map.put(:reuse_channels, reuse_channels)

    :telemetry.execute(@telemetry_event, %{@measurement => count}, tags)
  end
end
