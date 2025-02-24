defmodule RabbitMQPoolEx.Worker.RabbitMQConnectionTest do
  use ExUnit.Case, async: true

  alias RabbitMQPoolEx.Worker.RabbitMQConnection, as: ConnWorker

  setup do
    rabbitmq_config = [channels: 1]

    {:ok, config: rabbitmq_config}
  end

  describe "start_link/1" do
    test "creates a pool of channels based on config", %{config: config} do
      config = Keyword.put(config, :channels, 5)
      pid = start_supervised!({ConnWorker, config})

      %{channels: channels, connection: connection} = ConnWorker.state(pid)

      refute is_nil(connection)
      assert length(channels) == 5
    end

    test "creates a pool of channels using default config", %{config: config} do
      pid = start_supervised!({ConnWorker, Keyword.delete(config, :channels)})

      %{channels: channels} = ConnWorker.state(pid)

      assert length(channels) == 10
    end

    test "should reset state and schedule reconnect when connection is lost", %{config: config} do
      pid = start_supervised!({ConnWorker, config})

      %{channels: [_], connection: conn} = ConnWorker.state(pid)

      assert :ok == AMQP.Connection.close(conn)

      assert %{channels: [], connection: nil} = ConnWorker.state(pid)
    end
  end

  describe "checkout_channel/1" do
    test "successfully checkout a channel", %{config: config} do
      pid = start_supervised!({ConnWorker, config})

      assert {:ok, %{pid: channel_pid} = _channel} = ConnWorker.checkout_channel(pid)

      # Should monitor checked channels
      %{monitors: monitors} = ConnWorker.state(pid)

      assert monitors |> Map.get(channel_pid) |> is_reference()
    end

    test "return :out_of_channels when all channels are holded by clients", %{config: config} do
      pid = start_supervised!({ConnWorker, config})

      assert {:ok, channel} = ConnWorker.checkout_channel(pid)
      assert {:error, :out_of_channels} = ConnWorker.checkout_channel(pid)

      %{channels: channels, monitors: monitors} = ConnWorker.state(pid)

      assert Enum.empty?(channels)
      assert Kernel.map_size(monitors) == 1
      assert :ok = ConnWorker.checkin_channel(pid, channel)

      # Should demonitor after checkin
      %{channels: channels, monitors: monitors} = ConnWorker.state(pid)

      refute Enum.empty?(channels)
      assert Kernel.map_size(monitors) == 0
    end

    test "creates a new channel when a client holding it crashes", %{config: config} do
      pid = start_supervised!({ConnWorker, config})

      %{channels: [channel]} = ConnWorker.state(pid)

      client_pid =
        spawn(fn -> assert {:ok, channel} == ConnWorker.checkout_channel(pid) end)

      ref = Process.monitor(client_pid)

      assert_receive {:DOWN, ^ref, :process, ^client_pid, :normal}

      assert %{channels: channels, monitors: monitors} = ConnWorker.state(pid)

      assert length(channels) == 1
      assert Enum.empty?(monitors)
    end

    test "creates a new channel when it closes", %{config: config} do
      pid = start_supervised!({ConnWorker, config})

      %{channels: [%{pid: channel_pid} = channel]} = ConnWorker.state(pid)

      ref = Process.monitor(channel_pid)

      assert {:ok, channel} == ConnWorker.checkout_channel(pid)

      assert :ok == AMQP.Channel.close(channel)

      assert_receive {:DOWN, ^ref, :process, ^channel_pid, :normal}

      assert %{channels: [new_channel], monitors: monitors} = ConnWorker.state(pid)

      assert channel != new_channel

      assert Enum.empty?(monitors)
    end

    test "returns error when disconnected", %{config: config} do
      pid = start_supervised!({ConnWorker, config})

      %{channels: [_], connection: conn} = ConnWorker.state(pid)

      assert :ok == AMQP.Connection.close(conn)

      assert {:error, :disconnected} = ConnWorker.get_connection(pid)
      assert {:error, :disconnected} = ConnWorker.checkout_channel(pid)
    end
  end

  describe "checkin_channel/2" do
    test "should check channel in successfully", %{config: config} do
      pid = start_supervised!({ConnWorker, config})

      assert {:ok, channel} = ConnWorker.checkout_channel(pid)

      assert :ok == ConnWorker.checkin_channel(pid, channel)

      %{channels: [new_channel]} = ConnWorker.state(pid)

      assert channel != new_channel
    end

    test "should reuse channels", %{config: config} do
      config = Keyword.put(config, :reuse_channels?, true)
      pid = start_supervised!({ConnWorker, config})

      assert {:ok, channel} = ConnWorker.checkout_channel(pid)

      assert %{channels: []} = ConnWorker.state(pid)

      assert :ok == ConnWorker.checkin_channel(pid, channel)

      %{channels: [new_channel]} = ConnWorker.state(pid)

      assert channel == new_channel
    end

    test "should not replace channel when connection is lost", %{config: config} do
      pid = start_supervised!({ConnWorker, config})

      assert {:ok, channel} = ConnWorker.checkout_channel(pid)

      assert %{channels: [], connection: conn} = ConnWorker.state(pid)

      assert :ok == AMQP.Connection.close(conn)

      assert :ok == ConnWorker.checkin_channel(pid, channel)

      assert %{channels: []} = ConnWorker.state(pid)
    end

    test "should not add crashed channel back to channel pool", %{config: config} do
      pid = start_supervised!({ConnWorker, config})

      assert {:ok, %{pid: channel_pid} = channel} = ConnWorker.checkout_channel(pid)

      assert %{channels: []} = ConnWorker.state(pid)

      assert true == Process.exit(channel_pid, :normal)

      assert :ok == ConnWorker.checkin_channel(pid, channel)

      assert %{channels: [%{pid: new_channel_pid}]} = ConnWorker.state(pid)

      assert channel_pid != new_channel_pid
    end
  end
end
