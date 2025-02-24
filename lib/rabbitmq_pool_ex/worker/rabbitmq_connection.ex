defmodule RabbitMQPoolEx.Worker.RabbitMQConnection do
  @moduledoc """
  Worker module for managing RabbitMQ connections and channel pooling using `poolboy`.

  This module establishes and maintains a connection to RabbitMQ, manages a pool of channels,
  and handles reconnections and channel restarts in case of failures. It ensures that channels
  are efficiently reused and that clients can safely checkout and checkin channels.

  ## Configuration Options

    * `:reuse_channels` - When set to `true`, channels are reused when checked back into the pool. Defaults to `false`.
    * `:channels` - Number of channels to create in the pool. Defaults to 10.
    * `:reconnect_interval` - Interval in milliseconds to wait before attempting to reconnect. Defaults to 1000ms.
  """
  use GenServer

  require Logger

  @reconnect_interval :timer.seconds(1)
  @default_channels 10

  defmodule State do
    @moduledoc """
    Represents the state of the RabbitMQ connection worker.

    ## Fields

      * `:connection` - The active RabbitMQ connection.
      * `:channels` - List of channels available in the pool.
      * `:monitors` - Map of monitored processes holding channels.
      * `:config` - Configuration options provided when starting the worker.
      * `:reuse_channels` - Boolean indicating if channels are reused.
    """

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

  @doc """
  Starts the RabbitMQ connection worker.

  ## Parameters
    - `config` - Configuration options (keyword list or string).
  """
  @spec start_link(State.config()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, [])
  end

  @doc """
  Retrieves the current RabbitMQ connection.

  ## Parameters
    - `pid` - The PID of the worker process.
  """
  @spec get_connection(pid()) :: {:ok, AMQP.Connection.t()} | {:error, :disconnected}
  def get_connection(pid) do
    GenServer.call(pid, :conn)
  end

  @doc """
  Checks out a channel from the pool.

  It removes the channel from the available channels list
  and monitors the caller process (`from_pid`) to ensure proper cleanup in case of failure.

  ## Parameters:
  - `from_pid` (`pid`): The process identifier of the client (caller) that is requesting the channel.

  ## Behavior:
  - If there are available channels in the pool (`channels` list is non-empty), the function will:
    - Select the first channel (`channel`), remove it from the list of available channels (`channels: rest`), and add the caller process (`from_pid`) as a monitor for the channel.
    - The monitor reference is added to the `monitors` map, linking the `pid` of the channel to the new monitor reference.
    - The function returns a tuple containing the checked-out `channel` and the updated `state` with the modified list of channels and the updated monitor map.

  - If no channels are available, the function will raise an error or behave as defined in other parts of the system, though this behavior is not detailed here.
  """
  @spec checkout_channel(pid()) ::
          {:ok, AMQP.Channel.t()}
          | {:error, :disconnected}
          | {:error, :out_of_channels}
  def checkout_channel(pid) do
    GenServer.call(pid, :checkout_channel)
  end

  @doc """
  Checks a channel back into the pool.

  It takes care of reintegrating the channel into the state,
  ensuring the channel is properly monitored, and that the connection status is properly managed.

  The function behaves differently based on whether the channel reuse feature is enabled (`reuse_channels: true`) in the worker state.

  ## Parameters:
    - `pid` - The PID of the worker process.
    - `channel` - The channel to check back in.

  ## Behavior:
  - When `reuse_channels: true`:
    - If the channel's `pid` already exists in the pool (i.e., in the list of channels), it will simply remove the monitor for that `pid` and return the updated state.
    - If the `pid` is not already in the pool, it will add the channel to the list of channels and remove the monitor for that `pid` and return the updated state

  - When `reuse_channels` is not enabled:
    - If the channel's `pid` is found in either the list of channels or monitors, it will attempt to remove the channel from the pool and handle potential errors in case the channel has been closed.
    - If the channel's connection is still valid, it will replace the channel with a new one (close the current channel and open a new one).
    - If the connection is closed (`{:error, :closing}`), the state will simply be updated without re-adding the channel.
  """
  @spec checkin_channel(pid(), AMQP.Channel.t()) :: :ok
  def checkin_channel(pid, channel) do
    GenServer.cast(pid, {:checkin_channel, channel})
  end

  @doc """
  Creates a new channel outside of the pool.

  This allows clients to manually create channels without automatic management or pooling.

  ## Parameters
    - `pid` - The PID of the worker process.
  """
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
  Initializes the worker process by trapping exits, ensuring that all linked connections
  and multiplexed channels can be restarted by the worker.

  This function also triggers an asynchronous connection attempt, ensuring that any future
  calls will wait until the connection is successfully established.

  ## Parameters
  - `amqp_config` (keyword or string): RabbitMQ configuration settings used to establish the connection.
  """
  @impl true
  def init(amqp_config) do
    Process.flag(:trap_exit, true)

    reuse_channels = Keyword.get(amqp_config, :reuse_channels, false)

    send(self(), :connect)

    {:ok, %State{config: amqp_config, reuse_channels: reuse_channels}}
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

  @impl true
  def handle_call(:checkout_channel, {from_pid, _ref}, %State{} = state) do
    {channel, new_state} = checkout_channel(state, from_pid)

    {:reply, {:ok, channel}, new_state}
  end

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

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:connect, %State{} = state) do
    new_state =
      state
      |> connect()
      |> create_channels()

    {:noreply, new_state}
  end

  # Connection crashed/closed
  @impl true
  def handle_info(
        {:EXIT, conn_pid, reason},
        %{connection: %{pid: conn_pid}, config: config} = state
      ) do
    Logger.error(
      "[RabbitMQPoolEx] Connection lost, attempting to reconnect. Reason: #{inspect(reason)}"
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
    Logger.error(
      "[RabbitMQPoolEx] Connection lost, removing channel due to reason: #{inspect(reason)}"
    )

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
    Logger.warning("[RabbitMQPoolEx] Channel lost due to reason: #{inspect(reason)}")
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

  # If client holding a channel fails, then we need to take its channel back
  @impl true
  def handle_info(
        {:DOWN, down_ref, :process, _process_pid, _reason},
        %{channels: channels, monitors: monitors, connection: conn} = state
      ) do
    monitors
    |> find_monitor(down_ref)
    |> case do
      nil ->
        {:noreply, state}

      {pid, _ref} ->
        new_monitors = remove_monitor(monitors, pid)

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

  # Establishes a connection to RabbitMQ using the provided `amqp_config`.
  # If the connection is successfully established, it links the current process to the connection's process
  # for error handling.
  # If the connection attempt fails, it logs the error and schedules a retry.
  #
  # ## Parameters:
  # - `state` (`%State{}`): The current state of the pool.
  #
  # ## Behavior:
  # - The function attempts to open a connection to RabbitMQ using the configuration provided in `amqp_config`.
  # - If the connection is successfully established (`{:ok, connection}`):
  #   - The connection's process (`conn_pid`) is linked to the current process to handle errors and ensure
  #     that the connection and any associated channels are terminated if the current process dies.
  #   - The function returns the updated `state`, including the new connection.
  # - If the connection attempt fails (`{:error, reason}`):
  #   - An error log is generated, detailing the failure reason.
  #   - The function schedules a retry to establish the connection (using the `schedule_connect/1` function).
  #   - The original `state` is returned unchanged.
  defp connect(%State{config: amqp_config} = state) do
    amqp_config
    |> AMQP.Connection.open()
    |> case do
      {:ok, %{pid: conn_pid} = connection} ->
        Logger.info("[RabbitMQPoolEx] Successfully opened connection")

        # Link itself to the connection to handle connection errors
        # and also terminate the connection / channels if current
        # process dies.
        true = Process.link(conn_pid)

        %State{state | connection: connection}

      {:error, reason} ->
        Logger.error("[RabbitMQPoolEx] Failed to open connection. Reason: #{inspect(reason)}")

        schedule_connect(amqp_config)

        state
    end
  end

  # Creates a specified number of RabbitMQ channels and adds them to the state.
  # Each channel is linked to the current process to ensure proper error handling in case of failure.
  #
  # The number of channels to create is determined by the `:channels` configuration in the `amqp_config`.
  # If this value is not provided, the function defaults to a predefined number (`@default_channels`).
  #
  # ## Parameters:
  # - `state` (`%State{}`): The current state of the pool.
  #
  # ## Behavior:
  # - The function retrieves the desired number of channels from the configuration (`:channels`), defaulting to `
  #   @default_channels` if not specified.
  # - It then creates the specified number of channels by:
  #   - Starting each channel with the `start_channel/1` function.
  #   - Linking the current process to each created channel to handle errors (using `Process.link/1`).
  # - Then, the function returns the updated `state` with the newly created channels added to the `channels` list.
  defp create_channels(%State{config: amqp_config, connection: connection} = state) do
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

  defp checkin_chanel(%State{connection: conn} = state, %{pid: pid} = channel) do
    %{channels: channels, monitors: monitors} = state

    # Only start a new channel when checkin back a channel that isn't removed yet
    # this can happen when a channel crashed or is closed when a client holds it
    # so we get an `:EXIT` message and a `:checkin_channel` message in no given
    # order
    if find_channel(channels, pid, monitors) do
      new_channels = remove_channel(channels, pid)
      new_monitors = remove_monitor(monitors, pid)

      case replace_channel(channel, conn) do
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

  # Schedules a reconnection attempt to RabbitMQ after a specified interval.
  #
  # The interval is determined by the `:reconnect_interval` value in the provided configuration.
  # After the interval, a `:connect` message is sent to the current process to trigger the reconnection.
  #
  # TODO:
  #   * use exponential backoff to reconnect
  #   * use circuit breaker to fail fast
  # ## Parameters
  #   - `config` - Configuration options (keyword list or string).
  defp schedule_connect(config) do
    reconnect_interval = get_reconnect_interval(config)

    Logger.warning(
      "[RabbitMQPoolEx] Trying to reconect with RabbitMQ in #{reconnect_interval} seconds"
    )

    Process.send_after(self(), :connect, reconnect_interval)
  end

  # Opens a channel using the provided RabbitMQ connection.
  #
  # Each channel is backed by a `GenServer` process, so the worker is linked to these processes
  # to enable automatic restarts if a channel closes or crashes due to events like connection errors.
  #
  # ## Parameters
  #   - `connection` - The active RabbitMQ connection (`AMQP.Connection.t()`).
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

  defp find_channel(channels, channel_pid) do
    Enum.find(channels, &(&1.pid == channel_pid))
  end

  defp find_channel(channels, channel_pid, monitors) do
    Enum.find(channels, &(&1.pid == channel_pid)) || Map.get(monitors, channel_pid)
  end

  defp replace_channel(channel, _conn) when is_pid(channel) do
    case :amqp_channel.close(channel) do
      :ok -> :ok
      error -> {:error, error}
    end
  end

  defp replace_channel(%AMQP.Channel{pid: pid} = channel, conn) do
    true = Process.unlink(pid)

    AMQP.Channel.close(channel)

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
