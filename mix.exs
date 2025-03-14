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
      elixirc_paths: elixirc_paths(Mix.env()),
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
      name: @name,
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:poolboy, "~> 1.5"},
      {:amqp, "~> 3.0"},

      # Monitoring
      {:telemetry, "~> 1.3.0"},
      {:telemetry_metrics, "~> 1.1.0"},
      {:telemetry_poller, "~> 1.1.0"},

      # Docs
      {:ex_doc, "~> 0.16", only: :dev, runtime: false},

      # Testing and Dev Tools
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
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

  defp docs do
    [
      source_url: @source_url,
      main: "RabbitMQPoolEx",
      source_ref: "v#{version()}",
      groups_for_modules: [
        Overview: [
          RabbitMQPoolEx
        ],
        "RabbitMQ Adapters": [
          RabbitMQPoolEx.Ports.RabbitMQ,
          RabbitMQPoolEx.Adapters.RabbitMQ
        ],
        "Connection and Channel pools internals": [
          RabbitMQPoolEx.Worker.RabbitMQConnection,
          RabbitMQPoolEx.Worker.State
        ],
        "Telemetry Metrics": [
          RabbitMQPoolEx.Telemetry.Metrics.PoolSize
        ]
      ],
      extra_section: "DOCS",
      extras: ["CHANGELOG.md"],
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  defp before_closing_body_tag(:html) do
    """
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js"></script>
    <script>
      let initialized = false;

      window.addEventListener("exdoc:loaded", () => {
        if (!initialized) {
          mermaid.initialize({
            startOnLoad: false,
            theme: document.body.className.includes("dark") ? "dark" : "default"
          });
          initialized = true;
        }

        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""
end
