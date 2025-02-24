defmodule RabbitMQPoolEx.Adapters.FakeRabbitMQ do
  @moduledoc """
  This module is a dummy implementation of the `RabbitMQPoolEx.Ports.RabbitMQ` behavior, used for testing.
  """

  alias AMQP.Connection
  alias AMQP.Channel

  @behaviour RabbitMQPoolEx.Ports.RabbitMQ

  @impl true
  def open_connection(config) do
    case Keyword.get(config, :reply_error) do
      pid when is_pid(pid) ->
        error = {:error, {:connection, :invalid}}

        send(pid, error)

        error

      nil ->
        {:ok, %Connection{pid: generate_pid()}}
    end
  end

  @impl true
  def close_connection(_conn) do
    :ok
  end

  @impl true
  def open_channel(conn) do
    {:ok, %Channel{conn: conn, pid: generate_pid()}}
  end

  @impl true
  def close_channel(_channel) do
    :ok
  end

  defp generate_pid, do: spawn(fn -> Process.sleep(:infinity) end)
end
