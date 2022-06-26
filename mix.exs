# This file is only used by GrpcBox as a dependency.
# Use rebar3 instead for compiling, running tests, etc.
defmodule GrpcBox.MixProject do
  use Mix.Project

  {:ok, [{:application, :grpcbox, props}]} = :file.consult("src/grpcbox.app.src")
  @props Keyword.take(props, [:applications, :description, :env, :mod, :vsn])

  def application do
    @props
  end

  def project do
    [
      app: :grpcbox,
      version: to_string(application()[:vsn]),
      language: :erlang
    ]
  end

  def package do
    [
      name: :grpcbox
    ]
  end
end
