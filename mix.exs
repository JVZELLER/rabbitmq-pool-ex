defmodule RabbitMQPoolEx.MixProject do
  use Mix.Project

  @name "RabbitMQ Pool Ex"
  @source_url "https://github.com/JVZELLER/rabbitmq-pool-ex"

  def project do
    [
      app: :rabbitmq_pool_ex,
      version: version(),
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [
        plt_add_deps: :apps_direct,
        plt_add_apps: [:ex_unit, :mix, :amqp, :poolboy],
        list_unused_filters: true,
        # we use the following opt to change the PLT path
        # even though the opt is marked as deprecated, this is the doc-recommended way
        # to do this
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      # Hex
      description:
        "A lightweight Elixir library for managing RabbitMQ connection and channel pools.",
      package: package(),

      # Docs
      name: @name
    ]
  end

  defp version do
    "VERSION"
    |> File.read!()
    |> String.trim()
  end

  defp package do
    [
      maintainers: ["José Victor Zeller"],
      files: ~w(lib .formatter.exs mix.exs README* VERSION CHANGELOG*),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {RabbitMQPoolEx.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:poolboy, "~> 1.5"},
      {:amqp, "~> 4.0"},

      # Testing and Dev Tools
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
