defmodule RabbitMQPoolEx.Worker.RabbitMQConnection do
  @moduledoc """
  Default worker implementation for Poolboy.

  It's responsible for managing connection and channels poll.
  """
  use GenServer

  require Logger

  @reconnect_interval :timer.seconds(1)
  @default_channels 10

  defmodule State do
    @type config :: keyword() | String.t()

    @enforce_keys [:config]
    @type t :: %__MODULE__{
            connection: AMQP.Connection.t(),
            channels: list(AMQP.Channel.t()),
            monitors: %{},
            config: config(),
            reuse_channels: boolean()
          }

    defstruct connection: nil,
              channels: [],
              config: nil,
              monitors: %{},
              reuse_channels: false
  end

  ##############
  # Client API #
  ##############

  @spec start_link(State.config()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, [])
  end

  @spec get_connection(pid()) :: {:ok, AMQP.Connection.t()} | {:error, :disconnected}
  def get_connection(pid) do
    GenServer.call(pid, :conn)
  end

  @spec checkout_channel(pid()) ::
          {:ok, AMQP.Channel.t()}
          | {:error, :disconnected}
          | {:error, :out_of_channels}
  def checkout_channel(pid) do
    GenServer.call(pid, :checkout_channel)
  end

  @spec checkin_channel(pid(), AMQP.Channel.t()) :: :ok
  def checkin_channel(pid, channel) do
    GenServer.cast(pid, {:checkin_channel, channel})
  end

  @spec create_channel(pid()) :: {:ok, AMQP.Channel.t()} | {:error, any()}
  def create_channel(pid) do
    GenServer.call(pid, :create_channel)
  end

  @doc false
  def state(pid) do
    GenServer.call(pid, :state)
  end

  ####################
  # Server Callbacks #
  ####################

  @doc """
  Traps exits so all the linked connection and multiplexed channels can be
  restarted by this worker.
  Triggers an async connection but making sure future calls need to wait
  for the connection to happen before them.

    * `amqp_config` is the rabbitmq config settings
  """
  @impl true
  def init(amqp_config) do
    Process.flag(:trap_exit, true)

    reuse_channels = Keyword.get(config, :reuse_channels, false)

    send(self(), :connect)

    {:ok, %State{config: amqp_config, reuse_channels: reuse_channels}}
  end

  @impl true
  def handle_info(:connect, %State{} = state) do
    new_state =
      state
      |> connect()
      |> create_channels()

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:conn, _from, %State{connection: nil} = state) do
    {:reply, {:error, :disconnected}, state}
  end

  @impl true
  def handle_call(:conn, _from, %State{connection: connection} = state) do
    if Process.alive?(connection.pid) do
      {:reply, {:ok, connection}, state}
    else
      {:reply, {:ok, :disconnected}, state}
    end
  end

  @impl true
  def handle_call(:checkout_channel, _from, %State{connection: nil} = state) do
    {:reply, {:error, :disconnected}, state}
  end

  @impl true
  def handle_call(:checkout_channel, _from, %{channels: []} = state) do
    {:reply, {:error, :out_of_channels}, state}
  end

  # Checkout a channel out of a channel pool and monitors the client requesting
  # it so we can handle client crashes returning the monitor back to the pool
  @impl true
  def handle_call(:checkout_channel, {from_pid, _ref}, %State{} = state) do
    {channel, new_state} = checkout_channel(state, from_pid)

    {:reply, {:ok, channel}, new_state}
  end

  # Create a channel without linking the worker process to the channel pid, this
  # way clients can create channels on demand without the need of a pool, but
  # they are now in charge of handling channel crashes, connection closing,
  # channel closing, etc.
  @impl true
  def handle_call(:create_channel, _from, %{connection: conn} = state) do
    result = start_channel(conn)

    {:reply, result, state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:checkin_channel, channel}, %State{} = state) do
    new_state = checkin_chanel(state, channel)

    {:noreply, state}
  end

  # Connection crashed/closed
  @impl true
  def handle_info(
        {:EXIT, conn_pid, reason},
        %{connection: %{pid: conn_pid}, config: config} = state
      ) do
    Logger.error(
      "[RabbitMQPoolEx] connection lost, attempting to reconnect reason: #{inspect(reason)}"
    )

    schedule_connect(config)

    {:noreply, %State{state | connection: nil, channels: [], monitors: %{}}}
  end

  # Connection crashed so channels are going to crash too
  @impl true
  def handle_info(
        {:EXIT, channel_pid, reason},
        %{connection: nil, channels: channels, monitors: monitors} = state
      ) do
    Logger.error("[RabbitMQPoolEx] connection lost, removing channel reason: #{inspect(reason)}")
    new_channels = remove_channel(channels, channel_pid)
    new_monitors = remove_monitor(monitors, channel_pid)
    {:noreply, %State{state | channels: new_channels, monitors: new_monitors}}
  end

  # Channel crashed/closed, Connection crashed/closed
  @impl true
  def handle_info(
        {:EXIT, pid, reason},
        %{channels: channels, connection: conn, monitors: monitors} = state
      ) do
    Logger.warn("[RabbitMQPoolEx] channel lost reason: #{inspect(reason)}")
    # don't start a new channel if crashed channel doesn't belongs to the pool
    # anymore, this can happen when a channel crashed or is closed when a client holds it
    # so we get an `:EXIT` message and a `:checkin_channel` message in no given
    # order
    if find_channel(channels, pid, monitors) do
      new_channels = remove_channel(channels, pid)
      new_monitors = remove_monitor(monitors, pid)

      case start_channel(conn) do
        {:ok, channel} ->
          true = Process.link(channel.pid)
          {:noreply, %State{state | channels: [channel | new_channels], monitors: new_monitors}}

        {:error, :closing} ->
          # RabbitMQ Connection is closed. nothing to do, wait for reconnections
          {:noreply, %State{state | channels: new_channels, monitors: new_monitors}}
      end
    else
      {:noreply, state}
    end
  end

  # if client holding a channel fails, then we need to take its channel back
  @impl true
  def handle_info(
        {:DOWN, down_ref, :process, _process_pid, _reason},
        %{channels: channels, monitors: monitors, connection: conn} = state
      ) do
    find_monitor(monitors, down_ref)
    |> case do
      nil ->
        {:noreply, state}

      {pid, _ref} ->
        new_monitors = Map.delete(monitors, pid)

        case replace_channel(pid, conn) do
          {:ok, channel} ->
            {:noreply, %State{state | channels: [channel | channels], monitors: new_monitors}}

          {:error, :closing} ->
            # RabbitMQ Connection is closed. nothing to do, wait for reconnection
            {:noreply, %State{state | channels: channels, monitors: new_monitors}}
        end
    end
  end

  @impl true
  def terminate(_reason, %{connection: connection} = _state) do
    if connection && Process.alive?(connection.pid) do
      AMQP.Connection.close(connection)
    end
  end

  #############
  # Internals #
  #############

  defp connect(%State{config: amqp_config} = state) do
    amqp_config
    |> AMQP.Connection.open()
    |> case do
      {:ok, %{pid: conn_pid} = connection} ->
        Logger.info("[RabbitMQPoolEx] Successfully opened connection")

        # Link itself to the connection to handle connection errors
        true = Process.link(conn_pid)

        %State{state | connection: connection}

      {:error, reason} ->
        Logger.error("[RabbitMQPoolEx] Failed to open connection. Reason: #{inspect(reason)}")

        schedule_connect(amqp_config)

        state
    end
  end

  defp create_channels(%State{config: amqp_config} = state) do
    num_channels = Keyword.get(amqp_config, :channels, @default_channels)

    channels =
      Enum.map(num_channels, fn _n ->
        {:ok, channel} = start_channel(connection)

        # Link itself to the channel to handle errors
        true = Process.link(channel.pid)

        channel
      end)

    Logger.info("[RabbitMQPoolEx] Successfully created #{num_channels} Channels")

    %State{state | channels: channels}
  end

  defp checkout_channel(%State{channels: [channel | rest], monitors: monitors} = state, from_pid) do
    monitor_ref = Process.monitor(from_pid)
    new_monitors = Map.put_new(monitors, channel.pid, monitor_ref)

    {channel, %State{state | channels: rest, monitors: new_monitors}}
  end

  defp checkin_chanel(%State{reuse_channels: true} = state, %{pid: pid} = channel) do
    %{channels: channels, monitors: monitors} = state

    new_monitors = remove_monitor(monitors, pid)

    if find_channel(channels, pid) do
      %State{state | channels: channels, monitors: new_monitors}
    else
      %State{state | channels: channels ++ [channel], monitors: new_monitors}
    end
  end

  # When checkin back a channel to the pool is a good practice to not re-use
  # channels that are used with confirms, so, we need to remove it from the
  # channel list, unlink it and start a new one
  defp checkin_chanel(%State{} = state, %{pid: pid} = channel) do
    %{channels: channels, monitors: monitors} = state

    # Only start a new channel when checkin back a channel that isn't removed yet
    # this can happen when a channel crashed or is closed when a client holds it
    # so we get an `:EXIT` message and a `:checkin_channel` message in no given
    # order
    if find_channel(channels, pid, monitors) do
      new_channels = remove_channel(channels, pid)
      new_monitors = remove_monitor(monitors, pid)

      case replace_channel(pid, conn) do
        {:ok, channel} ->
          %State{state | channels: [channel | new_channels], monitors: new_monitors}

        {:error, :closing} ->
          # RabbitMQ Connection is closed. nothing to do, wait for reconnection
          %State{state | channels: new_channels, monitors: new_monitors}
      end
    else
      state
    end
  end

  # TODO: use exponential backoff to reconnect
  # TODO: use circuit breaker to fail fast
  defp schedule_connect(config) do
    interval = get_reconnect_interval(config)

    Logger.warning(
      "[RabbitMQPoolEx] Trying to reconect with RabbitMQ in #{reconnect_interval} seconds"
    )

    Process.send_after(self(), :connect, interval)
  end

  # Opens a channel using the specified client, each channel is backed by a
  # GenServer process, so we need to link the worker to all those processes
  # to be able to restart them when closed or when they crash e.g by a
  # connection error
  # TODO: maybe start channels on demand as needed and store them in the state for re-use
  @spec start_channel(AMQP.Connection.t()) :: {:ok, AMQP.Channel.t()} | {:error, any()}
  defp start_channel(%AMQP.Connection{pid: conn_pid} = connection) do
    if Process.alive?(conn_pid) do
      case AMQP.Channel.open(connection) do
        {:ok, _channel} = result ->
          Logger.debug("[RabbitMQPoolEx] channel connected")
          result

        {:error, reason} = error ->
          Logger.error("[RabbitMQPoolEx] Failed to create channel. Reason: #{inspect(reason)}")
          error

        error ->
          Logger.error(
            "[RabbitMQPoolEx] Failed to create channel due to unexpected error: #{inspect(error)}"
          )

          {:error, error}
      end
    else
      Logger.error("[RabbitMQPoolEx] Failed to create channel due to closed connection")

      {:error, :closing}
    end
  end

  defp get_reconnect_interval(config) do
    Keyword.get(config, :reconnect_interval, @reconnect_interval)
  end

  defp remove_channel(channels, channel_pid) do
    Enum.filter(channels, fn %{pid: pid} ->
      channel_pid != pid
    end)
  end

  defp remove_monitor(monitors, pid) when is_pid(pid) do
    case Map.get(monitors, pid) do
      nil ->
        monitors

      ref ->
        true = Process.demonitor(ref)
        Map.delete(monitors, pid)
    end
  end

  defp remove_monitor(monitors, monitor_ref) when is_reference(monitor_ref) do
    find_monitor(monitors, monitor_ref)
    |> case do
      nil ->
        monitors

      {pid, _} ->
        true = Process.demonitor(monitor_ref)
        Map.delete(monitors, pid)
    end
  end

  defp find_channel(channels, channel_pid, monitors) do
    Enum.find(channels, &(&1.pid == channel_pid)) || Map.get(monitors, channel_pid)
  end

  defp replace_channel(old_channel_pid, conn) do
    true = Process.unlink(old_channel_pid)

    AMQP.Channel.close(old_channel_pid)

    case start_channel(conn) do
      {:ok, channel} = result ->
        true = Process.link(channel.pid)
        result

      {:error, _reason} = error ->
        error
    end
  end

  defp find_monitor(monitors, ref) do
    Enum.find(monitors, fn {_pid, monitor_ref} -> monitor_ref == ref end)
  end
end
