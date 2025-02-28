defmodule RabbitMQPoolEx.Telemetry.Metrics.PoolSizeTest do
  use RabbitMQPoolEx.MonitorCase, async: true

  alias AMQP.Connection
  alias RabbitMQPoolEx.Telemetry.Metrics.PoolSize
  alias RabbitMQPoolEx.Worker.State
  alias Telemetry.Metrics

  @measurement :count
  @metric_name ~w(rabbitmq_pool_ex metrics pool_size #{@measurement})a
  @telemetry_event @metric_name -- [@measurement]
  @tags ~w(pool_id channels_count reuse_channels)a

  describe "metrics/0" do
    test "should return the metrics definition" do
      assert [
               %Metrics.LastValue{
                 name: @metric_name,
                 event_name: @telemetry_event,
                 measurement: @measurement,
                 tags: @tags,
                 description: "Tracks the latest pool size value."
               }
             ] = PoolSize.metrics()
    end
  end

  describe "execute/1" do
    test "should emit event successfully", ctx do
      attach(self(), ctx.test, @telemetry_event)

      state = state()

      pool_size = state.pool_size

      expected_tags =
        state
        |> Map.take(@tags)
        |> Map.put(:reuse_channels, state.reuse_channels?)

      assert :ok == PoolSize.execute(state)

      assert_received {:event, @telemetry_event, %{@measurement => ^pool_size}, ^expected_tags}
    end
  end

  defp state do
    %State{
      pool_id: :default_pool_id,
      connection: %Connection{pid: spawn(fn -> :ok end)},
      channels_count: 10,
      config: [],
      pool_size: 5,
      reuse_channels?: true
    }
  end
end
