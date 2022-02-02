defmodule Handler.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/SpiffInc/handler"

  def project do
    [
      app: :handler,
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [
        main: "Handler",
        logo: "handler.png",
        source_ref: "v#{@version}",
        source_url: @source_url,
        extras: ["README.md"]
      ],
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.22", only: :dev},
      {:benchee, "~> 1.0", only: :dev},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      description: "A helper to run functions that you want to limit by heap size or time",
      licenses: ["MIT"],
      links: %{
        "Github" => @source_url
      },
      maintainers: ["Michael Ries"]
    ]
  end
end
