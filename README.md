# RabbitMQPoolEx

[![Build Status](https://github.com/jvzeller/rabbitmq-pool-ex/actions/workflows/ci.yml/badge.svg)](https://github.com/jvzeller/rabbitmq-pool-ex/actions) [![Hex.pm](https://img.shields.io/hexpm/v/rabbitmq_pool_ex.svg)](https://hex.pm/packages/rabbitmq_pool_ex) [![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/rabbitmq_pool_ex/)

`rabbitmq_pool_ex` is an Elixir library that provides a robust and efficient connection pooling mechanism for RabbitMQ.
It leverages `poolboy` to manage a pool of connections, ensuring high performance and reliability in message-driven applications.

## Features

- **Connection Pooling**: Efficiently manage multiple RabbitMQ connections to handle high-throughput messaging.
- **Channel Management**: Simplify the process of acquiring and releasing channels from the connection pool.
- **Fault Tolerance**: Automatically handle connection drops and retries, ensuring minimal disruption to message
  processing.
- **Channel Reuse**: Optionally reuse channels within a pool to optimize resource management.
- **Configurable Pooling Strategy**: Customize the size, overflow, and behavior of connection pools.

## Installation

To integrate `rabbitmq_pool_ex` into your project, add the following to your `mix.exs` dependencies:

```elixir
defp deps do
  [
    {:rabbitmq_pool_ex, "~> 1.0.0"}
  ]
end
```

Then, fetch and install the dependencies by running:

```sh
mix deps.get
```

## Getting started

To use `rabbitmq_pool_ex`, add the following to your application's supervision tree:

```elixir
defmodule MyApp.Application do
  @moduledoc false

  @impl true
  def start(_type, _args) do
    children = [
      {RabbitMQPoolEx, get_pool_config()}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_pool_config do
    [
      rabbitmq_config: [host: "localhost", port: 5672],
      connection_pools: [
        %{
          name: {:local, :default_pool},
          size: 5,
          channels: 20,
          reuse_channels?: true,
          max_overflow: 2
        }
      ]
    ]
  end
end
```

and start interaction with RabbitMQ:

```elixir
RabbitMQPoolEx.with_channel(:rabbitmq_pool, fn
  {:ok, channel} ->
    AMQP.Basic.publish(channel, "exchange_name", "routing_key", "Hello, World!")
    :ok
  {:error, reason} ->
    IO.puts("Failed to acquire channel", error: inspect(reason))
end)
```

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request with improvements or bug fixes.

### Running Tests

To run tests locally:

```bash
make up

mix test
```

## License

`rabbitmq_pool_ex` is released under the Apache 2.0 License.

