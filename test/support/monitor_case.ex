defmodule RabbitMQPoolEx.MonitorCase do
  @moduledoc """
  This module defines the setup for monitors/metrics tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import RabbitMQPoolEx.MonitorCase
    end
  end

  @spec attach(pid(), any(), any()) :: :ok
  def attach(pid, handler_id, event) do
    :telemetry.attach(
      handler_id,
      event,
      fn event, measurements, metadata, _ ->
        send(pid, {:event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)
  end
end
