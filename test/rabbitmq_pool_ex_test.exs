defmodule RabbitMQPoolExTest do
  use ExUnit.Case, async: true

  alias RabbitMQPoolEx.PoolSupervisor

  setup do
    pool_id = :default_pool

    config = [
      connection_pools: [
        [
          name: {:local, pool_id},
          size: 1,
          channels: 1,
          reuse_channels?: true,
          max_overflow: 0
        ]
      ]
    ]

    {:ok, pool_id: pool_id, config: config}
  end

  describe "get_connection/1" do
    test "successfully retrieves a RabbitMQ connection from the pool", ctx do
      start_supervised!({PoolSupervisor, ctx.config})

      assert {:ok, conn} = RabbitMQPoolEx.get_connection(ctx.pool_id)
      assert is_pid(conn.pid)
    end

    test "should reconnect when connection is lost", ctx do
      start_supervised!({PoolSupervisor, ctx.config})

      assert {:ok, %{pid: conn_pid} = conn} = RabbitMQPoolEx.get_connection(ctx.pool_id)

      ref = Process.monitor(conn_pid)

      # Simulate connection loss
      Process.exit(conn_pid, :kill)

      assert_receive {:DOWN, ^ref, :process, ^conn_pid, :killed}

      # Before reconnection
      assert {:error, :disconnected} = RabbitMQPoolEx.get_connection(ctx.pool_id)

      # Waiting for reconnection
      Process.sleep(1_000)

      assert {:ok, new_connection} = RabbitMQPoolEx.get_connection(ctx.pool_id)
      assert conn != new_connection
    end
  end

  describe "get_connection_worker/1" do
    test "retrieves a connection worker from the pool", ctx do
      start_supervised!({PoolSupervisor, ctx.config})

      assert ctx.pool_id |> RabbitMQPoolEx.get_connection_worker() |> is_pid()
    end
  end

  describe "checkout_channel/1" do
    test "successfully checks out a channel", ctx do
      start_supervised!({PoolSupervisor, ctx.config})

      conn_worker_pid = RabbitMQPoolEx.get_connection_worker(ctx.pool_id)

      assert is_pid(conn_worker_pid)

      assert {:ok, channel} = RabbitMQPoolEx.checkout_channel(conn_worker_pid)
      assert is_pid(channel.pid)
    end

    test "returns :out_of_channels when all channels are held by clients", ctx do
      start_supervised!({PoolSupervisor, ctx.config})

      conn_worker_pid = RabbitMQPoolEx.get_connection_worker(ctx.pool_id)

      assert is_pid(conn_worker_pid)

      assert {:ok, _channel} = RabbitMQPoolEx.checkout_channel(conn_worker_pid)
      assert {:error, :out_of_channels} = RabbitMQPoolEx.checkout_channel(conn_worker_pid)
    end
  end

  describe "with_channel/2" do
    test "executes the given function within a channel's context", ctx do
      start_supervised!({PoolSupervisor, ctx.config})

      result =
        RabbitMQPoolEx.with_channel(ctx.pool_id, fn
          {:ok, channel} -> {:success, channel}
          {:error, reason} -> {:failure, reason}
        end)

      assert {:success, %AMQP.Channel{}} = result
    end

    test "handles errors when a channel cannot be acquired", ctx do
      start_supervised!({PoolSupervisor, ctx.config})

      conn_worker_pid = RabbitMQPoolEx.get_connection_worker(ctx.pool_id)

      assert is_pid(conn_worker_pid)

      # Will left no available channels
      assert {:ok, _channel} = RabbitMQPoolEx.checkout_channel(conn_worker_pid)

      result =
        RabbitMQPoolEx.with_channel(ctx.pool_id, fn
          {:ok, _channel} -> :ok
          {:error, reason} -> {:failure, reason}
        end)

      assert {:failure, :out_of_channels} = result
    end
  end

  describe "checkin_channel/2" do
    test "successfully checks a channel back into the pool", ctx do
      start_supervised!({PoolSupervisor, ctx.config})

      conn_worker_pid = RabbitMQPoolEx.get_connection_worker(ctx.pool_id)

      assert is_pid(conn_worker_pid)

      assert {:ok, channel} = RabbitMQPoolEx.checkout_channel(conn_worker_pid)
      assert :ok = RabbitMQPoolEx.checkin_channel(conn_worker_pid, channel)
    end

    test "does not check in a crashed channel", ctx do
      start_supervised!({PoolSupervisor, ctx.config})

      conn_worker_pid = RabbitMQPoolEx.get_connection_worker(ctx.pool_id)

      assert is_pid(conn_worker_pid)

      assert {:ok, %{pid: channel_pid} = channel} =
               RabbitMQPoolEx.checkout_channel(conn_worker_pid)

      assert ref = Process.monitor(channel_pid)

      # Simulate channel crash
      assert :ok == AMQP.Channel.close(channel)

      assert_receive {:DOWN, ^ref, :process, ^channel_pid, :normal}

      assert :ok == RabbitMQPoolEx.checkin_channel(conn_worker_pid, channel)

      assert {:ok, %{pid: new_channel_pid}} = RabbitMQPoolEx.checkout_channel(conn_worker_pid)

      assert channel_pid != new_channel_pid
    end
  end
end
