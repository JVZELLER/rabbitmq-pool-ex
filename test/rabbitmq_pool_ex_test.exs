defmodule RabbitMQPoolExTest do
  use ExUnit.Case
  doctest RabbitMQPoolEx

  test "greets the world" do
    assert RabbitMQPoolEx.hello() == :world
  end
end
