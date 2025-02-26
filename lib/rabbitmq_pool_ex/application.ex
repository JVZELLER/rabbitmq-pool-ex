defmodule RabbitMQPoolEx.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, args) do
    children = [
      {RabbitMQPoolEx.PoolSupervisor, args}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RabbitMQPoolEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
