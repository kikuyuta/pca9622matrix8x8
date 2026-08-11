defmodule PCA9622Matrix8x8.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/kikuyuta/pca9622matrix8x8"

  def project do
    [
      app: :pca9622matrix8x8,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:circuits_i2c, "~> 2.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Driver for the switch-science I2C 8x8 LED matrix board (PCA9622-based), " <>
      "with a bundled character generator for decimal and hexadecimal digits."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Product page" => "https://www.switch-science.com/products/2071",
        "Schematic" =>
          "http://doc.switch-science.com/schematic/PCA9622_aki_matrix/PCA9622_aki_matrix_sch.pdf"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
